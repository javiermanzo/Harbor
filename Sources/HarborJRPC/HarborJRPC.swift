//
//  HarborJRPC.swift
//
//
//  Created by Javier Manzo on 30/07/2024.
//

import Foundation

public final class HarborJRPC {
    private init() {}

    public static func configure(_ config: HJRPCConfig) {
        HJRPCRequestManager.config = config
    }
}
