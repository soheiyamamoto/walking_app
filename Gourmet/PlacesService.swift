//
//  PlacesService.swift
//  歩行練習サポートアプリ
//
//  周辺グルメ取得の抽象化（3.2）。
//   - 検索範囲: 半径 500m
//   - 抽出: 検索時点で「営業中」の店舗のみ
//   - 通信量対策: テキストと低解像度サムネ URL のみ取得。画像実体は View 側で遅延読み込み。
//
//  プロトコルで抽象化し、プロトタイプは MockPlacesService、本番は GooglePlacesService を差し替える。
//

import Foundation
import CoreLocation

// MARK: - モデル

/// 一覧表示用の店舗。通信量を抑えるため必要最小限のフィールドのみ保持する。
struct Restaurant: Identifiable, Equatable {
    let id: String
    let name: String
    let category: String
    let distanceMeters: Int
    let isOpenNow: Bool
    /// 「〜15:00」などの目安テキスト（提供元データに基づく / 断定しない）
    let closingText: String?
    /// 低解像度サムネ URL（実体は AsyncImage で遅延取得）
    let thumbnailURL: URL?

    var distanceText: String {
        distanceMeters < 1000 ? "\(distanceMeters)m"
                              : String(format: "%.1fkm", Double(distanceMeters) / 1000)
    }
}

// MARK: - プロトコル

protocol PlacesService {
    /// 指定地点の半径内で「営業中」の飲食店を距離順に返す。
    func nearbyOpenRestaurants(
        at location: CLLocation,
        radius: CLLocationDistance
    ) async throws -> [Restaurant]
}

enum PlacesError: Error {
    case offline
    case requestFailed
}

// MARK: - プロトタイプ用モック

/// API キー無しで挙動確認するためのモック。距離は基準地点からのダミー。
struct MockPlacesService: PlacesService {
    func nearbyOpenRestaurants(
        at location: CLLocation,
        radius: CLLocationDistance
    ) async throws -> [Restaurant] {
        // 通信を模した軽い遅延
        try? await Task.sleep(nanoseconds: 600_000_000)
        return [
            Restaurant(id: "1", name: "うどん処 豊前家", category: "うどん",
                       distanceMeters: 120, isOpenNow: true, closingText: "〜15:00",
                       thumbnailURL: nil),
            Restaurant(id: "2", name: "峠の茶屋カフェ", category: "カフェ",
                       distanceMeters: 280, isOpenNow: true, closingText: "〜18:00",
                       thumbnailURL: nil),
            Restaurant(id: "3", name: "定食 山道亭", category: "定食",
                       distanceMeters: 440, isOpenNow: true, closingText: "〜14:30",
                       thumbnailURL: nil),
        ].filter { $0.distanceMeters <= Int(radius) } // 半径 500m 内に限定
    }
}

// MARK: - 本番（Google Places API / Nearby Search の実装スケッチ）

/// Google Places API (New) を使う本番実装の骨子。
/// 通信量対策として FieldMask で取得フィールドを絞り、サムネは小さい maxWidthPx を指定する。
struct GooglePlacesService: PlacesService {
    let apiKey: String

    func nearbyOpenRestaurants(
        at location: CLLocation,
        radius: CLLocationDistance
    ) async throws -> [Restaurant] {
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchNearby")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        // 必要最小限のフィールドだけ要求 = レスポンス通信量を削減（3.2 通信量対策）。
        request.setValue(
            "places.id,places.displayName,places.location,places.regularOpeningHours,places.photos",
            forHTTPHeaderField: "X-Goog-FieldMask")

        let body: [String: Any] = [
            "includedTypes": ["restaurant", "cafe"],
            "maxResultCount": 10,
            "locationRestriction": [
                "circle": [
                    "center": ["latitude": location.coordinate.latitude,
                               "longitude": location.coordinate.longitude],
                    "radius": radius   // 500m
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw PlacesError.requestFailed
        }

        // 注: 実際のパースは Codable で行う。openNow == true のみ採用し距離順にソートする。
        //     サムネは places.photos の name から
        //     "/media?maxWidthPx=120&key=..." で低解像度 URL を組み立てる。
        _ = data
        return [] // ← デコード実装はプロジェクト側で補完
    }
}
