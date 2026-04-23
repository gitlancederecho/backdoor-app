//
//  BackdoorApp.swift
//  Backdoor
//
//  Created by lance on 2026/04/21.
//

import SwiftUI

@main
struct BackdoorApp: App {
    @State private var auth = AuthViewModel()
    @State private var lang = LanguageManager.shared
    @State private var venue = VenueViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
                .environment(lang)
                .environment(venue)
        }
    }
}
