//
//  HarborJRPC.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

public final class HarborJRPC {
    private init() {}

    public static func setURL(_ url: String) {
        HJRPCRequestManager.config.url = url
    }

    public static func setJRPCVersion(_ jrpcVersion: String) {
        HJRPCRequestManager.config.jrpcVersion = jrpcVersion
    }
}
