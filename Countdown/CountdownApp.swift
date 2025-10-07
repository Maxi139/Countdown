//
//  CountdownApp.swift
//  Countdown
//
//  Created by Maximilian Schmidt on 02.10.25.
//

import SwiftUI

@main
struct CountdownApp: App {
    @StateObject private var store = EventStore()

    var body: some Scene {
        WindowGroup {
            NavigationView {
                EventListView()
                    .environmentObject(store)
            }
        }
    }
}
