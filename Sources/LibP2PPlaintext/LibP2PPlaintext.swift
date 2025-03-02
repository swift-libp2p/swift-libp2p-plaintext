//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-libp2p open source project
//
// Copyright (c) 2022-2025 swift-libp2p project authors
// Licensed under MIT
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of swift-libp2p project authors
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import LibP2P

public enum PlaintextErrors:Error {
    case invalidPeerIDExchange
}

public struct PlaintextUpgrader: SecurityUpgrader {
    
    public static let key:String = "/plaintext/2.0.0"
    let application:Application
    
    init(application:Application) {
        self.application = application
        self.application.logger.trace("PlaintextV2: Initializing")
    }
    
    public func upgradeConnection(_ conn: Connection, position:ChannelPipeline.Position, securedPromise: EventLoopPromise<Connection.SecuredResult>) -> EventLoopFuture<Void> {
        // Given a ChannelHandlerContext Configure and Install our HandshakeHandler onto the pipeline
        let handlers:[ChannelHandler] = [
            InboundPlaintextV2DecryptHandler(
                peerID: conn.localPeer,
                mode: conn.mode,
                logger: conn.logger,
                secured: securedPromise
            ),
            OutboundPlaintextV2EncryptHandler(
                mode: conn.mode,
                logger: conn.logger
            )
        ]
        return conn.channel.pipeline.addHandlers( handlers, position: position )
    }
    
    public func printSelf() {
        application.logger.notice("Hi I'm the PlaintextV2 security protocol")
    }
}
