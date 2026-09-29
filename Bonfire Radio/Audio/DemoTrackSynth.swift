import Foundation
import AVFAudio
import Synchronization

/// 저작권 없는 절차적 로파이 데모 트랙.
/// 모든 소리는 곡 시간 `t`의 순수 함수이므로, 시작 시각만 공유하면 참가자 기기들이 같은 소리를 낸다.
nonisolated final class DemoTrackSynth: @unchecked Sendable {
    static let title = "밤의 모닥불 (Lo-fi 데모)"

    private struct Control {
        var isPlaying = false
        var songTimeAtStart: Double = 0
        var framesRendered: Int64 = 0
        var gain: Float = 0.9
    }

    private let control = Mutex(Control())
    let sampleRate: Double
    let format: AVAudioFormat
    private(set) var node: AVAudioSourceNode!
    /// 렌더된 샘플을 그대로 분석해 비트 반응 지연을 최소화한다.
    let analyzer: AudioAnalyzer

    // 84 BPM, 4/4, 4바 진행(Am – F – C – G)
    private let bpm: Double = 84
    private var beatLength: Double { 60 / bpm }
    private var barLength: Double { beatLength * 4 }
    private let bassRoots: [Double] = [55.0, 43.65, 65.41, 49.0]
    private let padChords: [[Double]] = [
        [220.0, 261.63, 329.63],
        [174.61, 220.0, 261.63],
        [261.63, 329.63, 392.0],
        [196.0, 246.94, 293.66]
    ]
    private let bassPattern: [Bool] = [true, false, false, true, true, false, true, false]

    init(sampleRate: Double = 48_000) {
        self.sampleRate = sampleRate
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        self.analyzer = AudioAnalyzer(sampleRate: sampleRate)
        self.node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            return self.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
        }
    }

    var isPlaying: Bool {
        control.withLock { $0.isPlaying }
    }

    /// 현재 곡 위치(초).
    var currentTime: Double {
        control.withLock { $0.songTimeAtStart + Double($0.framesRendered) / sampleRate }
    }

    func play(from songTime: Double) {
        control.withLock {
            $0.songTimeAtStart = max(0, songTime)
            $0.framesRendered = 0
            $0.isPlaying = true
        }
    }

    func pause() {
        control.withLock { $0.isPlaying = false }
    }

    private func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let (playing, startTime, rendered, gain) = control.withLock { ($0.isPlaying, $0.songTimeAtStart, $0.framesRendered, $0.gain) }
        guard buffers.count >= 1 else { return noErr }
        let left = buffers[0].mData?.assumingMemoryBound(to: Float.self)
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil

        if !playing {
            for i in 0..<frameCount {
                left?[i] = 0
                right?[i] = 0
            }
            return noErr
        }

        for i in 0..<frameCount {
            let sampleIndex = rendered + Int64(i)
            let t = startTime + Double(sampleIndex) / sampleRate
            let (l, r) = sample(at: t, sampleIndex: sampleIndex)
            left?[i] = tanh(l * gain)
            right?[i] = tanh(r * gain)
        }
        control.withLock { $0.framesRendered += Int64(frameCount) }

        if let left {
            var pointers: [UnsafeMutablePointer<Float>] = [left]
            if let right { pointers.append(right) }
            pointers.withUnsafeBufferPointer { ptr in
                analyzer.process(channels: ptr.baseAddress!, channelCount: pointers.count, frames: frameCount, sampleRate: sampleRate)
            }
        }
        return noErr
    }

    /// 곡 시간 t에서의 스테레오 샘플.
    private func sample(at t: Double, sampleIndex: Int64) -> (Float, Float) {
        let bar = Int(floor(t / barLength)) % 4
        let barT = t - floor(t / barLength) * barLength
        let beatIndex = Int(floor(t / beatLength)) % 4
        let beatT = t - floor(t / beatLength) * beatLength
        let eighthLength = beatLength / 2
        let eighthIndex = Int(floor(t / eighthLength)) % 8
        let eighthT = t - floor(t / eighthLength) * eighthLength
        let barIndexAbsolute = Int(floor(t / barLength))

        // 킥: 1·3박 + 짝수 바에서 2.5박 고스트
        var kick = 0.0
        let kickHit = beatIndex == 0 || beatIndex == 2 || (barIndexAbsolute % 2 == 1 && eighthIndex == 3)
        if kickHit {
            let kt = (barIndexAbsolute % 2 == 1 && eighthIndex == 3) ? eighthT : beatT
            let env = exp(-kt * 9)
            let phase = 2 * Double.pi * (48 * kt + (90 / 25) * (1 - exp(-25 * kt)))
            kick = sin(phase) * env * 0.9
        }

        // 베이스
        var bass = 0.0
        if bassPattern[eighthIndex] {
            let root = bassRoots[bar]
            let env = 0.25 + 0.75 * exp(-eighthT * 4)
            bass = (sin(2 * Double.pi * root * t) + 0.35 * sin(2 * Double.pi * root * 2 * t)) * env * 0.32
        }

        // 하이햇: 결정론적 노이즈
        let hatEnv = exp(-eighthT * 55)
        let hatGain = eighthIndex % 2 == 0 ? 0.11 : 0.05
        let hat = Double(Self.noise(UInt64(bitPattern: sampleIndex))) * hatEnv * hatGain

        // 패드: 3음 코드, 느린 어택, 트레몰로
        let chord = padChords[bar]
        let padEnv = min(1, barT * 1.5) * (0.85 + 0.15 * sin(2 * Double.pi * 0.2 * t))
        var padL = 0.0
        var padR = 0.0
        for (index, freq) in chord.enumerated() {
            let detune = Double(index) * 0.3
            let tone = sin(2 * Double.pi * (freq + detune) * t) + 0.5 * sin(2 * Double.pi * (freq * 2 + detune) * t)
            let pan = Double(index) / Double(chord.count - 1)
            padL += tone * (1 - pan * 0.6)
            padR += tone * (0.4 + pan * 0.6)
        }
        padL *= padEnv * 0.06
        padR *= padEnv * 0.06

        let mono = kick + bass + hat
        return (Float(mono + padL), Float(mono + padR))
    }

    /// -1...1 결정론적 해시 노이즈.
    private static func noise(_ i: UInt64) -> Float {
        var x = i &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 29
        x &*= 0xBF58_476D_1CE4_E5B9
        x ^= x >> 32
        return Float(x & 0xFF_FFFF) / Float(0xFF_FFFF) * 2 - 1
    }
}
