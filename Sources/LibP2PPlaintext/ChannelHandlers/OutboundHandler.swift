//
//  OutboundHandler.swift
//  
//
//  Created by Brandon Toms on 5/1/22.
//

import LibP2P

// Version 2.0.0 (PeerID Exchange)
internal final class OutboundPlaintextV2EncryptHandler: ChannelOutboundHandler {
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    private var logger:Logger
    
    public init(mode:LibP2PCore.Mode, logger:Logger) {
        self.logger = logger
        
        self.logger[metadataKey: "PlaintextV2"] = .string("outbound.\(mode.rawValue)")
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        //let readable = buffer.readableBytesView
        //logger.trace(String(data: Data(readable), encoding: .utf8) ?? "NIL")
        logger.trace("--- 🔒 Outbound Data Fauxcryption Complete 🔒 ---")
        
        context.write( wrapOutboundOut(buffer), promise: nil)
    }
    
    // Flush it out. This can make use of gathering writes if multiple buffers are pending
    public func channelWriteComplete(context: ChannelHandlerContext) {
        //logger.trace("Write Complete")
        context.flush()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("Error: \(error)")
        
        context.close(promise: nil)
    }
}
