import SwiftUI
import GroupActivities
import OSLog

private let logger = Logger(subsystem: "com.coulson.BonfireRadio", category: "app")

/// 앱 전역 상태. 방장 권위 모델: 방 상태의 진실은 방장 기기.
@Observable
final class AppModel {
    enum Mode: Equatable {
        case idle
        case solo
        case shared
    }

    // MARK: 상태
    var mode: Mode = .idle
    var roomState = RoomState()
    var isHost = false
    var localDisplayName = "방장"
    var statusMessage: String?

    // 이머시브
    var immersiveOpen = false
    var wantsImmersive = false
    var immersionStyle: any ImmersionStyle = .full
    /// 다른 참가자가 이머시브를 열었을 때 "함께 들어가기" 제안을 표시한다.
    var groupImmersiveSuggestion = false

    // SharePlay
    var session: SessionController?
    private var pendingHostClaim = false
    private var appliedNowPlaying: NowPlaying?

    // 던지기(패널 폴백 버튼 → 이머시브 씬 소비)
    var throwQueue: [ThrowableKind] = []
    var lastLandedKind: ThrowableKind?
    var remoteThrowBursts: [ThrowEvent] = []

    // 음원 입력
    var streamURLText = ""

    let audio = BroadcastAudioEngine()
    private var tintResetTask: Task<Void, Never>?
    private var nonce: UInt64 = 0

    var participantCount: Int {
        session?.participantCount ?? 1
    }

    var canControlBroadcast: Bool {
        mode == .solo || isHost
    }

    // MARK: 솔로

    func startSolo() {
        session?.leave()
        session = nil
        mode = .solo
        isHost = true
        roomState = RoomState()
        roomState.hostDisplayName = localDisplayName
        appliedNowPlaying = nil
        audio.configureSession(allowMic: false)
        audio.start()
        wantsImmersive = true
        statusMessage = nil
    }

    // MARK: 방 만들기 / 참가

    func createRoom() async {
        pendingHostClaim = true
        let activity = RadioActivity()
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            do {
                _ = try await activity.activate()
            } catch {
                logger.error("activate 실패: \(error.localizedDescription)")
                pendingHostClaim = false
                statusMessage = "FaceTime 통화가 없습니다. '초대해서 방 만들기'로 참가자를 먼저 초대해 주세요."
            }
        case .activationDisabled:
            pendingHostClaim = false
            statusMessage = "SharePlay를 사용할 수 없어 혼자 불멍으로 시작합니다."
            startSolo()
        case .cancelled:
            pendingHostClaim = false
        @unknown default:
            pendingHostClaim = false
        }
    }

    /// 앱 수명 동안 세션을 관찰한다(초대 수락으로 실행된 경우 포함).
    func observeSessions() async {
        for await groupSession in RadioActivity.sessions() {
            await join(groupSession)
        }
    }

    private func join(_ groupSession: GroupSession<RadioActivity>) async {
        session?.leave()
        guard let controller = await SessionController(session: groupSession, appModel: self) else {
            statusMessage = "공간 SharePlay를 지원하지 않는 세션입니다."
            return
        }
        session = controller
        mode = .shared
        isHost = false
        roomState = RoomState()
        appliedNowPlaying = nil
        audio.configureSession(allowMic: false)
        audio.start()
        audio.streamPlayer.coordinate(with: groupSession)
        statusMessage = nil
    }

    func sessionDidJoin() {
        guard let session else { return }
        if pendingHostClaim {
            pendingHostClaim = false
            claimHost()
        }
        // 방장은 세션 확립 후 이머시브를 연다(공유 좌표계 점프 방지).
        if isHost {
            wantsImmersive = true
        }
        logger.notice("세션 joined, 로컬 \(session.localParticipantID)")
    }

    func sessionDidInvalidate() {
        session = nil
        if mode == .shared {
            mode = .idle
            isHost = false
            audio.stop()
            wantsImmersive = false
            statusMessage = "SharePlay 세션이 종료되었습니다."
        }
    }

    func participantsJoined(_ newcomers: Set<Participant>) {
        guard isHost, let session else { return }
        session.send(.snapshot(roomState), to: .only(newcomers))
        session.send(.hostAnnounce(participantID: session.localParticipantID, name: localDisplayName), to: .only(newcomers))
    }

    func groupImmersionChanged(isOpen: Bool) {
        if isOpen, !immersiveOpen, !wantsImmersive {
            groupImmersiveSuggestion = true
        } else if !isOpen {
            groupImmersiveSuggestion = false
        }
    }

    private func claimHost() {
        guard let session else { return }
        isHost = true
        roomState.hostParticipantID = session.localParticipantID
        roomState.hostDisplayName = localDisplayName
        bumpSeq()
        session.send(.hostAnnounce(participantID: session.localParticipantID, name: localDisplayName))
        session.send(.snapshot(roomState))
    }

    // MARK: 메시지 처리

    func handle(message: RoomMessage, from participantID: UUID) {
        switch message {
        case .snapshot(let incoming):
            guard !isHost else { return }
            guard incoming.seq > roomState.seq || roomState.seq == 0 else { return }
            let previousNowPlaying = roomState.nowPlaying
            roomState = incoming
            if incoming.nowPlaying != previousNowPlaying {
                applyNowPlaying(incoming.nowPlaying)
            }
        case .requestTint(let tint, _):
            guard isHost else { return }
            setTint(tint)
        case .throwItem(let event):
            guard event.participantID != session?.localParticipantID else { return }
            remoteThrowBursts.append(event)
        case .hostAnnounce(let id, let name):
            if isHost, let mine = session?.localParticipantID, id != mine {
                // 동시 선언 시 UUID 문자열이 작은 쪽이 방장.
                if id.uuidString < mine.uuidString {
                    isHost = false
                    roomState.hostParticipantID = id
                    roomState.hostDisplayName = name
                }
            } else if !isHost {
                roomState.hostParticipantID = id
                roomState.hostDisplayName = name
            }
        }
    }

    // MARK: 불 색

    /// 아이템이 불에 닿았을 때(로컬 물리에서 발생).
    func throwLanded(kind: ThrowableKind) {
        lastLandedKind = kind
        nonce &+= 1
        if canControlBroadcast {
            setTint(kind.tint)
        } else {
            // 낙관적 적용 후 방장 스냅샷으로 확정.
            roomState.tint = kind.tint
            roomState.tintChangedAt = .now
            session?.send(.requestTint(kind.tint, nonce: nonce))
        }
        if let session {
            session.sendUnreliable(.throwItem(ThrowEvent(kind: kind, participantID: session.localParticipantID, nonce: nonce)))
        }
    }

    func setTint(_ tint: FlameTint) {
        roomState.tint = tint
        roomState.tintChangedAt = .now
        bumpSeq()
        broadcastSnapshot()
        scheduleTintReset()
    }

    func resetTint() {
        setTint(.default)
    }

    private func scheduleTintReset() {
        tintResetTask?.cancel()
        guard roomState.tint != .default, canControlBroadcast else { return }
        tintResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled, let self, canControlBroadcast else { return }
            setTint(.default)
        }
    }

    func setIntensity(_ value: Float) {
        roomState.intensity = value
        bumpSeq()
        broadcastSnapshot()
    }

    func setReduceFlicker(_ value: Bool) {
        roomState.reduceFlicker = value
        bumpSeq()
        broadcastSnapshot()
    }

    private func bumpSeq() {
        guard canControlBroadcast else { return }
        roomState.seq &+= 1
    }

    private func broadcastSnapshot() {
        guard isHost, let session else { return }
        session.send(.snapshot(roomState))
    }

    // MARK: 음원 (방장/솔로)

    func playDemo() {
        let nowPlaying = NowPlaying(source: .demo, title: DemoTrackSynth.title, streamURL: nil,
                                    isPlaying: true, startedAt: .now, positionAtStart: 0)
        updateNowPlaying(nowPlaying)
    }

    func playStream() {
        let trimmed = streamURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, scheme.hasPrefix("http") else {
            statusMessage = "올바른 스트림 URL(http/https)을 입력하세요."
            return
        }
        let nowPlaying = NowPlaying(source: .stream, title: url.host() ?? "스트림", streamURL: url,
                                    isPlaying: true, startedAt: .now, positionAtStart: 0)
        updateNowPlaying(nowPlaying)
    }

    func playHostFile(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            try audio.playFile(url: url)
            let nowPlaying = NowPlaying(source: .hostFile, title: url.deletingPathExtension().lastPathComponent, streamURL: nil,
                                        isPlaying: true, startedAt: .now, positionAtStart: 0)
            roomState.nowPlaying = nowPlaying
            appliedNowPlaying = nowPlaying
            bumpSeq()
            broadcastSnapshot()
        } catch {
            statusMessage = "파일을 재생할 수 없습니다: \(error.localizedDescription)"
        }
    }

    func togglePlayback() {
        guard var nowPlaying = roomState.nowPlaying else { return }
        if nowPlaying.isPlaying {
            let position = currentPlaybackPosition(of: nowPlaying)
            nowPlaying.isPlaying = false
            nowPlaying.positionAtStart = position
            nowPlaying.startedAt = .now
        } else {
            nowPlaying.isPlaying = true
            nowPlaying.startedAt = .now
        }
        updateNowPlaying(nowPlaying)
    }

    func stopMusic() {
        updateNowPlaying(nil)
    }

    private func currentPlaybackPosition(of nowPlaying: NowPlaying) -> TimeInterval {
        switch nowPlaying.source {
        case .demo: audio.synth.currentTime
        case .stream: nowPlaying.positionAtStart + Date.now.timeIntervalSince(nowPlaying.startedAt)
        case .hostFile: 0
        }
    }

    private func updateNowPlaying(_ nowPlaying: NowPlaying?) {
        guard canControlBroadcast else { return }
        roomState.nowPlaying = nowPlaying
        applyNowPlaying(nowPlaying)
        bumpSeq()
        broadcastSnapshot()
    }

    /// 스냅샷의 재생 상태를 로컬 오디오에 반영한다(방장·참가자 공통).
    private func applyNowPlaying(_ nowPlaying: NowPlaying?) {
        guard appliedNowPlaying != nowPlaying else { return }
        appliedNowPlaying = nowPlaying
        guard let nowPlaying else {
            audio.pauseDemo()
            audio.stopFile()
            audio.streamPlayer.stop()
            return
        }
        switch nowPlaying.source {
        case .demo:
            audio.streamPlayer.pause()
            audio.stopFile()
            if nowPlaying.isPlaying {
                audio.playDemo(startedAt: nowPlaying.startedAt, positionAtStart: nowPlaying.positionAtStart)
            } else {
                audio.pauseDemo()
            }
        case .stream:
            audio.pauseDemo()
            audio.stopFile()
            if let url = nowPlaying.streamURL {
                audio.streamPlayer.load(url: url, title: nowPlaying.title)
                if nowPlaying.isPlaying {
                    audio.streamPlayer.play()
                } else {
                    audio.streamPlayer.pause()
                }
            }
        case .hostFile:
            // 참가자 기기에는 파일이 없다. 방장 기기만 재생(이미 playHostFile에서 처리).
            if !canControlBroadcast {
                audio.pauseDemo()
                audio.streamPlayer.pause()
            }
        }
    }

    // MARK: 던지기 폴백

    func enqueueThrow(_ kind: ThrowableKind) {
        throwQueue.append(kind)
    }

    // MARK: 마이크

    func toggleMic() async {
        if audio.micState == .on {
            audio.disableMic()
        } else {
            await audio.enableMic()
        }
    }

    // MARK: 종료

    func leaveRoom() {
        tintResetTask?.cancel()
        if isHost, mode == .shared {
            session?.endForEveryone()
        } else {
            session?.leave()
        }
        session = nil
        mode = .idle
        isHost = false
        wantsImmersive = false
        groupImmersiveSuggestion = false
        audio.stop()
        appliedNowPlaying = nil
        roomState = RoomState()
    }
}
