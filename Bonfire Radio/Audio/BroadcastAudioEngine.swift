import Foundation
import AVFAudio
import OSLog

private let logger = Logger(subsystem: "com.coulson.BonfireRadio", category: "audio")

/// 방장 송출 및 로컬 재생 엔진. 데모 트랙 신스, 방장 파일 재생, 마이크 레벨 모니터, 스트림 플레이어를 묶는다.
@Observable
final class BroadcastAudioEngine {
    enum MicState: Equatable {
        case off
        case on
        case unavailable(String)
    }

    let engine = AVAudioEngine()
    let synth = DemoTrackSynth()
    let streamPlayer = StreamPlayer()
    private let filePlayer = AVAudioPlayerNode()
    /// 믹서 탭(파일 재생 분석용)
    private let mixAnalyzer = AudioAnalyzer()
    private let micAnalyzer = AudioAnalyzer()

    private(set) var isRunning = false
    private(set) var micState: MicState = .off
    private(set) var isFilePlaying = false
    private var graphBuilt = false
    private var micTapInstalled = false
    private var currentCategory: AVAudioSession.Category?

    var volume: Float = 0.8 {
        didSet {
            engine.mainMixerNode.outputVolume = volume
            streamPlayer.volume = volume
        }
    }

    // MARK: 세션

    func configureSession(allowMic: Bool) {
        let category: AVAudioSession.Category = allowMic ? .playAndRecord : .playback
        guard currentCategory != category else { return }
        currentCategory = category
        // setActive는 메인 스레드에서 호출하면 UI가 멈출 수 있어 백그라운드에서 수행한다.
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(category, mode: .default, options: [])
                try session.setActive(true)
            } catch {
                logger.error("오디오 세션 설정 실패: \(error.localizedDescription)")
            }
        }
    }

    // MARK: 엔진

    private func buildGraphIfNeeded() {
        guard !graphBuilt else { return }
        engine.attach(synth.node)
        engine.attach(filePlayer)
        engine.connect(synth.node, to: engine.mainMixerNode, format: synth.format)
        engine.connect(filePlayer, to: engine.mainMixerNode, format: nil)
        let analyzer = mixAnalyzer
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { @Sendable buffer, _ in
            analyzer.process(buffer)
        }
        engine.mainMixerNode.outputVolume = volume
        graphBuilt = true
    }

    func start() {
        configureSession(allowMic: micState == .on)
        buildGraphIfNeeded()
        guard !engine.isRunning else { isRunning = true; return }
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            logger.error("오디오 엔진 시작 실패: \(error.localizedDescription)")
            isRunning = false
        }
    }

    func stop() {
        synth.pause()
        filePlayer.stop()
        isFilePlaying = false
        streamPlayer.stop()
        disableMic()
        engine.stop()
        isRunning = false
        mixAnalyzer.reset()
    }

    // MARK: 데모 트랙

    func playDemo(startedAt: Date, positionAtStart: TimeInterval) {
        start()
        stopFile()
        streamPlayer.pause()
        let elapsed = max(0, Date.now.timeIntervalSince(startedAt))
        synth.play(from: positionAtStart + elapsed)
    }

    func pauseDemo() {
        synth.pause()
        synth.analyzer.reset()
    }

    // MARK: 방장 파일

    func playFile(url: URL) throws {
        start()
        synth.pause()
        streamPlayer.pause()
        let file = try AVAudioFile(forReading: url)
        engine.disconnectNodeOutput(filePlayer)
        engine.connect(filePlayer, to: engine.mainMixerNode, format: file.processingFormat)
        filePlayer.stop()
        filePlayer.scheduleFile(file, at: nil)
        filePlayer.play()
        isFilePlaying = true
    }

    func stopFile() {
        guard isFilePlaying else { return }
        filePlayer.stop()
        isFilePlaying = false
        mixAnalyzer.reset()
    }

    // MARK: 마이크 (솔로 모드 / 방장)

    func enableMic() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            micState = .unavailable("마이크 권한이 없습니다")
            return
        }
        let wasRunning = engine.isRunning
        engine.stop()
        currentCategory = nil
        configureSession(allowMic: true)
        buildGraphIfNeeded()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            micState = .unavailable("이 기기에서 마이크 입력을 사용할 수 없습니다")
            if wasRunning { start() }
            return
        }
        if !micTapInstalled {
            let analyzer = micAnalyzer
            input.installTap(onBus: 0, bufferSize: 1024, format: nil) { @Sendable buffer, _ in
                analyzer.process(buffer)
            }
            micTapInstalled = true
        }
        micState = .on
        start()
    }

    func disableMic() {
        if micTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            micTapInstalled = false
        }
        micAnalyzer.reset()
        if micState == .on { micState = .off }
    }

    // MARK: 레벨

    /// 현재 활성 음원의 레벨을 합성한다(30Hz로 시각 레이어가 호출).
    func currentLevels() -> AudioLevels {
        var levels = AudioLevels.silent
        if synth.isPlaying { levels = .max(levels, synth.analyzer.latest) }
        if isFilePlaying { levels = .max(levels, mixAnalyzer.latest) }
        if streamPlayer.isPlaying { levels = .max(levels, streamPlayer.levels) }
        if micState == .on { levels = .max(levels, micAnalyzer.latest) }
        return levels
    }
}
