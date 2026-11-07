//
//  ExportSettingsView.swift
//  Movie Editor
//

import SwiftUI

struct ExportSettingsView: View {
    @AppStorage(ExportCodec.storageKey) private var codec = ExportCodec.h264.rawValue

    var body: some View {
        Form {
            Picker("Export codec", selection: $codec) {
                ForEach(ExportCodec.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize()
    }
}
