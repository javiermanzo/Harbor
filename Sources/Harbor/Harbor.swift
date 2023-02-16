//
//  Harbor.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

public class Harbor {
    
    internal static var authProvider: HAuthProviderProtocol?
    
    private init() {}
    
    public static func setAuthProvider(_ authProvider: HAuthProviderProtocol) {
        self.authProvider = authProvider
    }
}
