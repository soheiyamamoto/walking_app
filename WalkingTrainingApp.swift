//
//  WalkingTrainingApp.swift
//  歩行練習サポートアプリ
//
//  アプリのエントリポイント。最初の画面は AppRootView
//  （初回はオンボーディング、2 回目以降は本体タブ）。
//

import SwiftUI

@main
struct WalkingTrainingApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
