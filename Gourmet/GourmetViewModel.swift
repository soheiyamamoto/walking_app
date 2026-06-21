//
//  GourmetViewModel.swift
//  歩行練習サポートアプリ
//
//  周辺グルメ画面の状態管理（3.2 全体の制御ロジック）。
//
//  状態遷移の要点:
//   - オフライン時は loadState=.offline で待機（通信しない）。
//   - 復帰時（NetworkMonitor.onReconnect）に現在地基準で自動再取得。
//   - 100m 以上移動しても自動取得せず、showUpdateBanner を立ててユーザーのタップを待つ（デバウンス）。
//

import Foundation
import CoreLocation

@MainActor
final class GourmetViewModel: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded([Restaurant])
        case empty            // 半径内に営業中の店が無い
        case offline          // オフライン待機
        case locationDenied   // 位置情報が拒否されている
        case failed
    }

    @Published private(set) var state: LoadState = .idle

    /// 「100m 以上移動しました／この場所で更新」バナーの表示可否。
    var showUpdateBanner: Bool { location.movedSinceLastSearch && network.isOnline }

    let location: LocationProvider
    let network: NetworkMonitor
    private let places: PlacesService
    private let searchRadius: CLLocationDistance = 500   // 半径 500m（仕様 3.2）

    init(location: LocationProvider,
         network: NetworkMonitor,
         places: PlacesService = MockPlacesService()) {
        self.location = location
        self.network = network
        self.places = places
    }

    /// 画面表示時のセットアップ。
    func onAppear() {
        location.requestAuthorizationIfNeeded()

        // オフライン → オンライン復帰の瞬間に、現在地で自動再取得する（仕様 3.2）。
        network.onReconnect = { [weak self] in
            Task { await self?.search(reason: .reconnect) }
        }
        network.start()

        location.startMonitoringMovement()

        // 初回取得（オンライン時のみ）。
        if network.isOnline {
            location.requestOneShotLocation()
            Task { await search(reason: .initial) }
        } else {
            state = .offline
        }
    }

    func onDisappear() {
        location.stopMonitoringMovement()
        network.stop()
    }

    /// ユーザーのワンタップによる手動更新（移動バナー or 更新ボタン）。
    func refreshTapped() {
        location.requestOneShotLocation()
        Task { await search(reason: .manual) }
    }

    // MARK: - 検索本体

    private enum SearchReason { case initial, manual, reconnect }

    private func search(reason: SearchReason) async {
        // オフラインなら通信せず待機状態へ。
        guard network.isOnline else { state = .offline; return }

        guard location.isAuthorized else {
            state = location.authorization == .denied ? .locationDenied : .idle
            return
        }

        // 現在地が未取得なら少し待ってから基準を確定（ワンショット測位の到着待ち）。
        guard let here = await resolveCurrentLocation() else {
            state = .failed
            return
        }

        state = .loading
        do {
            let results = try await places.nearbyOpenRestaurants(at: here, radius: searchRadius)
            // 念のためクライアント側でも「営業中」「半径内」を保証し距離順に整列。
            let filtered = results
                .filter { $0.isOpenNow && $0.distanceMeters <= Int(searchRadius) }
                .sorted { $0.distanceMeters < $1.distanceMeters }

            location.markSearched(at: here)        // 基準地点を更新し移動フラグをリセット
            state = filtered.isEmpty ? .empty : .loaded(filtered)
        } catch {
            state = .failed
        }
    }

    /// ワンショット測位が届くまで短くポーリングして現在地を確定する。
    private func resolveCurrentLocation() async -> CLLocation? {
        if let loc = location.currentLocation { return loc }
        for _ in 0..<10 {                          // 最大 ~2 秒待つ
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let loc = location.currentLocation { return loc }
        }
        return nil
    }
}
