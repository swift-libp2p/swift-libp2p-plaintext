//
//  InboundHandler.swift
//  
//
//  Created by Brandon Toms on 5/1/22.
//

import LibP2P

/// Plaintext V2
///
/// https://github.com/libp2p/specs/blob/master/plaintext/README.md
/// Version 2.0.0 (PeerID Exchange)
///
/// Misc Notes:
/// PlaintextV2 DOES NOT Require uVarInt length based frame encoding/decoding
/// The handshake / peerID exchange is uVarInt prefixed, but after that, it should simply forward data along.
internal final class InboundPlaintextV2DecryptHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    private enum State {
        case awaitingPeerID
        case verified
    }
    
    private var channelSecuredCallback:EventLoopPromise<Connection.SecuredResult>
    
    private var state:State
    
    private var logger:Logger
    private let localPeerInfo:PeerID
    private var remotePeerInfo:PeerID? = nil
            
    public init(peerID:PeerID, mode:LibP2PCore.Mode, logger: Logger, secured:EventLoopPromise<Connection.SecuredResult>) {
        self.localPeerInfo = peerID
        self.state = .awaitingPeerID
        self.logger = logger
        self.channelSecuredCallback = secured
        
        self.logger[metadataKey: "PlaintextV2"] = .string("inbound.\(mode.rawValue)")
    }
    
    /// We take this opportunity to send our PeerExchange protobuf
    public func handlerAdded(context: ChannelHandlerContext) {
        do {
            self.logger.trace("Sending our local peer info to remote peer")
            
            /// ----------------- Support Go ----------------
            let peerInfo = try self.localPeerInfo.marshal()
            /// ---------------------------
            
            /// ----------------- Support JS ----------------
            //let peerInfo = try createExchangeMessage(localPeerInfo)
            /// ---------------------------
            
            let payload = putUVarInt(UInt64(peerInfo.count)) + peerInfo
            
            self.logger.trace("\(payload.asString(base: .base16))")
            self.logger.trace("Count: \(payload.count)")
            
            // Write the serialized data to a buffer
            let buf = context.channel.allocator.buffer(bytes: payload)
            
            // Send our peer info off to the remote host...
            context.writeAndFlush( self.wrapOutboundOut(buf), promise: nil)
            
        } catch {
            self.logger.error("Failed to instantiate our PeerInfo Exchange protobuf")
            self.logger.error("Error: \(error)")
            self.logger.error("Closing Channel")
            // TODO: We should probably fail better than this...
            channelSecuredCallback.fail(error)
            context.fireErrorCaught(error)
            context.close(mode: .all, promise: nil)
        }
    }
    
    private var buffer:[UInt8] = []
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch state {
        case .awaitingPeerID:
            //We're expecting an Exchange Protobuf object thats uVarInt length Prefixed, if it's not that then we abort...
            let buf = unwrapInboundIn(data)
            
            let msg = buffer + Array<UInt8>(buf.readableBytesView)
            let prefix = uVarInt(msg)
            guard prefix.bytesRead > 0, prefix.value > 1 else {
                self.logger.error("Failed to parse inbound Plaintext/2.0.0 Handshake message")
                channelSecuredCallback.fail(PlaintextErrors.invalidPeerIDExchange)
                return context.close(mode: .all, promise: nil)
            }
            
            if prefix.value > msg.count {
                //Partial Read Detected, waiting for more info!
                buffer = msg
                return
            }
            
            //msg = Array(msg.dropFirst(prefix.bytesRead))
            let peerInfo = Array(msg[prefix.bytesRead..<(prefix.bytesRead + Int(prefix.value))])
            let leftoverData = msg[(prefix.bytesRead + Int(prefix.value))...]
            
            do {
                logger.trace("\(peerInfo.asString(base: .base16))")
                logger.trace("Bytes: \(peerInfo.count)")
               
                let exchangeMessage = try Exchange(contiguousBytes: peerInfo)
                if let pid = try? PeerID(marshaledPeerID: Data(peerInfo)) {
                    self.logger.trace("Incoming Message straight to PeerID (no exchange proto) => \(pid.b58String)")
                    remotePeerInfo = pid
                } else {
                    remotePeerInfo = try PeerID(marshaledPublicKey: exchangeMessage.pubkey.data) //.serializedData())
                }
                
                guard remotePeerInfo!.id == exchangeMessage.id.bytes else {
                    logger.error("Remote Peer ID isn't derived from their PublicKey. Closing connection.")
                    //self.channelSecuredCallback.succeed((false, nil))
                    self.channelSecuredCallback.fail( PlaintextErrors.invalidPeerIDExchange )
                    return context.close(mode: .all, promise: nil)
                }
                logger.trace("Peer Info from Remote Peer seems legit, let's proceed")
                logger.trace("PeerID: \(remotePeerInfo!.b58String)")
                // Construct the Multiaddr that we know so far...
                logger.trace("RemoteAddress:Protocol => \(String(describing: context.channel.remoteAddress?.protocol ?? .none))")
                logger.trace("RemoteAddress:Protocol => \(context.channel.remoteAddress?.ipAddress ?? "nil")")
                logger.trace("RemoteAddress:Protocol => \(context.channel.remoteAddress?.port ?? -1)")
                logger.trace("RemoteAddress:Protocol => \(context.channel.remoteAddress?.pathname ?? "nil")")
                
                // Upgrade our state so that all future messages will be propogated through the pipeline
                state = .verified
                
                // Remove our uVarInt Length Prefix Handlers now that our handshake is complete. Then satisfy our channelSecuredCallback if all goes as planned.
                self.channelSecuredCallback.succeed(
                    (PlaintextUpgrader.key, self.remotePeerInfo, nil)
                )
                
                /// We cascade off of the channelSecuredCallback's futureResult to ensure the upgrader has had time to prepare the Pipeline before sending additional messages along it.
                /// - Note: If we instead forwarded data along the pipeline in the completeWith handler above, MSS would get a channelRead before having time to finalize the security upgrade and prepare the muxer negotiator.
                let _ = self.channelSecuredCallback.futureResult.always { _ in
                    self.logger.trace("ChannelSecuredCallback futureResult.always called")
                    if leftoverData.count > 0 {
                        self.logger.trace("--- 🔓 Forwarding leftover handshake data 🔓 ---")
                        context.fireChannelRead( self.wrapInboundOut( context.channel.allocator.buffer(bytes: leftoverData) ) )
                    }
                }
            } catch {
                logger.error("Failed to instantiate an Exchange Protobuf from the inbound data")
                logger.error("Error: \(error)")
                channelSecuredCallback.fail(error)
                context.close(mode: .all, promise: nil)
            }
        case .verified:
            // Simply forward the data along the pipeline
            logger.trace("--- 🔓 Inbound Data Decryption Complete 🔓 ---")
            context.fireChannelRead( wrapInboundOut( unwrapInboundIn(data) ) )
        }
    }
    
    /// Given a peerID, this method handles building an Exchange protobuf
    private func createExchangeMessage(_ peerID:PeerID) throws -> Data {
        let keyType:Exchange.KeyType
        switch peerID.keyPair!.keyType {
        case .rsa:
            keyType = .rsa
        case .ed25519:
            keyType = .ed25519
        case .secp256k1:
            keyType = .secp256K1
        }
        
        var pubkey = Exchange.PublicKey()
        pubkey.type = keyType
        pubkey.data = try Data(peerID.marshalPublicKey())
        
        var exch = Exchange()
        exch.id = Data(peerID.id)
        exch.pubkey = pubkey
        
        return try exch.serializedData()
    }
    
    public enum Errors:Error {
        case failedToRemoveEphemeralHandshakeHandlersFromPipeline
    }
}
