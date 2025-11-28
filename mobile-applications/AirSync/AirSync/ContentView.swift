//
//  ContentView.swift
//  AirSync
//
//  Created by Jack Darnell on 11/27/25.
//

import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var browser = ReceiverBrowser()
    @State private var manualHost: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Discovered Receivers")) {
                    if browser.receivers.isEmpty {
                        Text(browser.isScanning ? "Scanning the local network..." : "No receivers found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(browser.receivers) { receiver in
                            NavigationLink(destination: CalibrationView(session: .liveReceiverSession(baseURL: receiver.baseURL))) {
                                VStack(alignment: .leading) {
                                    Text(receiver.displayName)
                                        .font(.headline)
                                    Text(receiver.host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Manual Address")) {
                    HStack {
                        TextField("receiver.local or IP", text: $manualHost)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        if let url = manualURL {
                            NavigationLink("Calibrate", destination: CalibrationView(session: .liveReceiverSession(baseURL: url)))
                        }
                    }
                }
            }
            .navigationTitle("Select Receiver")
            .toolbar {
                Button {
                    browser.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .onAppear {
                browser.start()
            }
        }
    }

    private var manualURL: URL? {
        guard !manualHost.isEmpty else { return nil }
        return URL(string: "http://\(manualHost):5000")
    }
}

#Preview {
    ContentView()
}
