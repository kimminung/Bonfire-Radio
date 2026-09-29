import Foundation

/// 현재 재생 중인 음원 정보. 방장 시계(startedAt) 기준으로 참가자가 위치를 맞춘다.
nonisolated struct NowPlaying: Codable, Sendable, Equatable {
    nonisolated enum Source: String, Codable, Sendable {
        case demo
        case stream
        case hostFile
    }

    var source: Source
    var title: String
    var streamURL: URL?
    var isPlaying: Bool
    /// 방장이 `positionAtStart` 위치에서 재생을 (재)시작한 시각.
    var startedAt: Date
    var positionAtStart: TimeInterval

    var sourceLabel: String {
        switch source {
        case .demo: "데모 트랙"
        case .stream: "스트림"
        case .hostFile: "방장 파일"
        }
    }
}

/// 방의 공유 상태. 방장 기기가 진실의 원천이며 `seq`가 큰 스냅샷만 적용한다.
nonisolated struct RoomState: Codable, Sendable, Equatable {
    var seq: UInt64 = 0
    var hostParticipantID: UUID?
    var hostDisplayName: String = ""
    var tint: FlameTint = .wood
    var tintChangedAt: Date = .distantPast
    var intensity: Float = 1.0
    var reduceFlicker: Bool = false
    var nowPlaying: NowPlaying?
}

/// 던지기 이벤트(시각 효과 재현용, 비신뢰 전송).
nonisolated struct ThrowEvent: Codable, Sendable {
    var kind: ThrowableKind
    var participantID: UUID
    var nonce: UInt64
}

/// GroupSessionMessenger 페이로드.
nonisolated enum RoomMessage: Codable, Sendable {
    case snapshot(RoomState)
    case requestTint(FlameTint, nonce: UInt64)
    case throwItem(ThrowEvent)
    case hostAnnounce(participantID: UUID, name: String)
}
