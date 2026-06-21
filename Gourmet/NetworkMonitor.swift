//
//  NetworkMonitor.swift
//  歩行練習サポートアプリ
//
//  オンライン / オフラインの監視と「復帰」検知（3.2 オンライン/オフライン制御）。
//
//  設計方針:
//   - オフライン時はグルメ機能を待機状態にし、通信を一切行わない（4.2 不要通信の排除）。
//   - オフライン → オンラインへ「変化した瞬間」を onReconnect で通知し、
//     呼び出し側が現在地基準で自動再取得できるようにする。
//

import Foundation
import Network

@MainActor
final class NetworkMonitor: ObservableObject {

    @Published private(set) var isOnline = true

    /// オフライン → オンラインへ復帰した瞬間に呼ばれる。
    var onReconnect: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var wasOnline = true

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let didReconnect = (self.wasOnline == false && online == true)
                self.wasOnline = online
                self.isOnline = online
                if didReconnect {
                    // 復帰した「時点」で 1 回だけ通知（毎更新では呼ばない）。
                    self.onReconnect?()
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
