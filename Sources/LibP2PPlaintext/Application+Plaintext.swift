//
//  Application+Plaintext.swift
//  
//
//  Created by Brandon Toms on 5/1/22.
//

import LibP2P

extension Application.SecurityUpgraders.Provider {
    public static var plaintextV2: Self {
        .init {
            $0.security.use { app in
                return PlaintextUpgrader(application: app)
            }
        }
    }
}
