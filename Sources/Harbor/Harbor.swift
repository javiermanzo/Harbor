//
//  Harbor.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public final class Harbor {

    private init() {}

    public static func configure(_ config: HConfig) {
        HRequestManager.config = config
    }
}
