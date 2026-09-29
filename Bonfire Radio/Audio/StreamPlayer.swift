import Foundation
import AVFoundation
import GroupActivities

/// 인터넷 라디오/HLS URL 재생기. SharePlay 세션이 있으면 AVPlaybackCoordinator로 rate/time을 동기화한다.
@Observable
final class StreamPlayer {
    let player = AVPlayer()
    private(set) var isPlaying = false
    private(set) var title = ""
    private(set) var currentURL: URL?

    var volume: Float = 0.8 {
        didSet { player.volume = volume }
    }

    init() {
        player.volume = volume
        player.automaticallyWaitsToMinimizeStalling = true
    }

    func load(url: URL, title: String) {
        guard currentURL != url else { return }
        currentURL = url
        self.title = title
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        isPlaying = false
    }

    func coordinate(with session: GroupSession<RadioActivity>) {
        player.playbackCoordinator.coordinateWithSession(session)
    }

    /// v1: 스트림 탭 분석 전까지는 은은한 기본 반응만 제공한다.
    var levels: AudioLevels {
        guard isPlaying else { return .silent }
        return AudioLevels(bass: 0.35, mid: 0.30, treble: 0.25, rms: 0.30, beat: 0, isActive: true)
    }
}
