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

// Version 2.0.0 (PeerID Exchange)
internal final class OutboundPlaintextV2EncryptHandler: ChannelOutboundHandler {
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private var logger: Logger

    public init(mode: LibP2PCore.Mode, logger: Logger) {
        self.logger = logger

        self.logger[metadataKey: "PlaintextV2"] = .string("outbound.\(mode.rawValue)")
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        //let readable = buffer.readableBytesView
        //logger.trace(String(data: Data(readable), encoding: .utf8) ?? "NIL")
        logger.trace("--- 🔒 Outbound Data Fauxcryption Complete 🔒 ---")

        context.write(wrapOutboundOut(buffer), promise: nil)
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
