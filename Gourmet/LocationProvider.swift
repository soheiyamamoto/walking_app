//
//  LocationProvider.swift
//  歩行練習サポートアプリ
//
//  グルメ検索のための位置情報プロバイダ。
//
//  設計方針（4.2 省電力 / 論点「移動閾値100m + 手動更新デバウンス」）:
//   - 連続測位はしない。distanceFilter = 100m で「100m 以上動いた時だけ」delegate が発火。
//     これだけで実質バッテリーに優しい移動検知になる。
//   - 移動を検知しても自動では再検索しない。movedSinceLastSearch を立てるだけ。
//     再検索はユーザーのワンタップ（手動更新）に委ねる = デバウンス。
//   - 初回／手動更新時のワンショット測位は requestLocation() を使う。
//

import Foundation
import CoreLocation

@MainActor
final class LocationProvider: NSObject, ObservableObject {

    /// 直近の現在地（検索の基準に使う）
    @Published private(set) var currentLocation: CLLocation?

    /// 前回検索した地点から 100m 以上移動したか。
    /// true の間だけ「この場所で更新」バナーを出す（自動取得はしない）。
    @Published private(set) var movedSinceLastSearch = false

    /// 位置情報の利用可否（拒否時はグルメ機能を無効化し案内を出す）
    @Published private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()

    /// 「移動した」とみなす閾値（m）。距離フィルタ兼用。
    private let moveThreshold: CLLocationDistance = 100

    /// 最後に検索を実行した地点。movedSinceLastSearch 判定の基準。
    private var lastSearchLocation: CLLocation?

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters // 省電力優先
        manager.distanceFilter = moveThreshold
    }

    func requestAuthorizationIfNeeded() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// 初回表示・手動更新時のワンショット測位。
    func requestOneShotLocation() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    /// 100m 以上の移動を継続監視する（distanceFilter により発火は間引かれる）。
    func startMonitoringMovement() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    func stopMonitoringMovement() {
        manager.stopUpdatingLocation()
    }

    /// 検索を実行した時に呼ぶ。基準地点を更新し、移動フラグをリセットする。
    func markSearched(at location: CLLocation) {
        lastSearchLocation = location
        movedSinceLastSearch = false
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }
}

extension LocationProvider: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            currentLocation = latest
            // 前回検索地点から閾値以上離れたら、バナー表示用フラグを立てる（自動取得はしない）。
            if let base = lastSearchLocation,
               latest.distance(from: base) >= moveThreshold {
                movedSinceLastSearch = true
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // ワンショット失敗時は黙ってリトライ余地を残す（呼び出し側が手動更新で再試行可能）。
    }
}
