//
//  ContentView.swift
//  YMindApp
//
//  Created by 李仁军 on 2026/9/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var session = DocumentSession()

    var body: some View {
        ZStack(alignment: .top) {
            CanvasMetalView(session: session)

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .accessibilityLabel("画布错误：\(errorMessage)")
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

#Preview {
    ContentView()
}
