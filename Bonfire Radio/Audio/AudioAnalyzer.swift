import Foundation
import Accelerate
import AVFAudio
import Synchronization

/// 시각 레이어가 소비하는 정규화(0...1) 오디오 레벨.
nonisolated struct AudioLevels: Sendable, Equatable {
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var rms: Float = 0
    /// 비트 온셋에서 1로 튀고 감쇠한다.
    var beat: Float = 0
    var isActive: Bool = false

    static let silent = AudioLevels()

    static func max(_ a: AudioLevels, _ b: AudioLevels) -> AudioLevels {
        AudioLevels(bass: Swift.max(a.bass, b.bass),
                    mid: Swift.max(a.mid, b.mid),
                    treble: Swift.max(a.treble, b.treble),
                    rms: Swift.max(a.rms, b.rms),
                    beat: Swift.max(a.beat, b.beat),
                    isActive: a.isActive || b.isActive)
    }
}

/// 오디오 스레드에서 샘플을 받아 FFT 밴드 에너지·RMS·비트를 계산한다.
/// `process`는 단일 오디오 스레드에서만 호출한다(스크래치 버퍼는 잠금 없이 사용).
nonisolated final class AudioAnalyzer: @unchecked Sendable {
    private struct Published {
        var levels = AudioLevels()
    }

    private struct Tracking {
        var bassMax: Float = 1e-5
        var midMax: Float = 1e-5
        var trebleMax: Float = 1e-5
        var rmsMax: Float = 1e-3
        var bassAvg: Float = 0
        var lastBeatTime: Double = -1
        var clock: Double = 0
        var smoothed = AudioLevels()
    }

    private let published = Mutex(Published())

    private let n = 1024
    private let hop = 256
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private var ring: [Float]
    private var ringWrite = 0
    private var sinceAnalysis = 0
    private var frame: [Float]
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]
    private var magnitudes: [Float]
    private var tracking = Tracking()
    private var sampleRate: Double

    init(sampleRate: Double = 48_000) {
        self.sampleRate = sampleRate
        let log2n = vDSP_Length(log2(Float(n)))
        guard let setup = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else {
            fatalError("FFT setup failed")
        }
        fft = setup
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        ring = [Float](repeating: 0, count: n)
        frame = [Float](repeating: 0, count: n)
        realIn = [Float](repeating: 0, count: n / 2)
        imagIn = [Float](repeating: 0, count: n / 2)
        realOut = [Float](repeating: 0, count: n / 2)
        imagOut = [Float](repeating: 0, count: n / 2)
        magnitudes = [Float](repeating: 0, count: n / 2)
    }

    /// 최근 계산된 레벨(메인 스레드에서 읽기 안전).
    var latest: AudioLevels {
        published.withLock { $0.levels }
    }

    func reset() {
        tracking = Tracking()
        published.withLock { $0.levels = .silent }
    }

    /// AVAudioPCMBuffer(비인터리브 Float32)를 분석한다.
    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        sampleRate = buffer.format.sampleRate
        process(channels: channels, channelCount: channelCount, frames: count, sampleRate: buffer.format.sampleRate)
    }

    /// 채널 포인터 배열을 직접 분석한다(소스 노드 렌더 경로용).
    func process(channels: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int, frames: Int, sampleRate: Double) {
        guard channelCount > 0, frames > 0 else { return }
        self.sampleRate = sampleRate
        let scale = 1 / Float(channelCount)
        for i in 0..<frames {
            var mono: Float = 0
            for c in 0..<channelCount {
                mono += channels[c][i]
            }
            ring[ringWrite] = mono * scale
            ringWrite = (ringWrite + 1) % n
            sinceAnalysis += 1
            if sinceAnalysis >= hop {
                sinceAnalysis = 0
                analyze()
            }
        }
    }

    private func analyze() {
        // 링 버퍼를 시간순으로 펼친다.
        for i in 0..<n {
            frame[i] = ring[(ringWrite + i) % n]
        }
        let rmsRaw = vDSP.rootMeanSquare(frame)
        vDSP.multiply(frame, window, result: &frame)
        for i in 0..<(n / 2) {
            realIn[i] = frame[2 * i]
            imagIn[i] = frame[2 * i + 1]
        }
        realIn.withUnsafeMutableBufferPointer { rIn in
            imagIn.withUnsafeMutableBufferPointer { iIn in
                realOut.withUnsafeMutableBufferPointer { rOut in
                    imagOut.withUnsafeMutableBufferPointer { iOut in
                        let input = DSPSplitComplex(realp: rIn.baseAddress!, imagp: iIn.baseAddress!)
                        var output = DSPSplitComplex(realp: rOut.baseAddress!, imagp: iOut.baseAddress!)
                        fft.forward(input: input, output: &output)
                        vDSP.squareMagnitudes(output, result: &magnitudes)
                    }
                }
            }
        }

        let binHz = Float(sampleRate) / Float(n)
        let bassRaw = bandPower(lowHz: 40, highHz: 200, binHz: binHz)
        let midRaw = bandPower(lowHz: 200, highHz: 2_000, binHz: binHz)
        let trebleRaw = bandPower(lowHz: 2_000, highHz: 8_000, binHz: binHz)

        tracking.clock += Double(hop) / sampleRate
        let dt = Float(Double(hop) / sampleRate)

        // 자동 게인: 느리게 감쇠하는 최대값으로 정규화한다.
        let decay: Float = 1 - 0.35 * dt
        tracking.bassMax = max(bassRaw, tracking.bassMax * decay, 1e-6)
        tracking.midMax = max(midRaw, tracking.midMax * decay, 1e-6)
        tracking.trebleMax = max(trebleRaw, tracking.trebleMax * decay, 1e-7)
        tracking.rmsMax = max(rmsRaw, tracking.rmsMax * decay, 1e-3)

        let isActive = rmsRaw > 0.0025
        var target = AudioLevels(
            bass: isActive ? sqrt(min(1, bassRaw / tracking.bassMax)) : 0,
            mid: isActive ? sqrt(min(1, midRaw / tracking.midMax)) : 0,
            treble: isActive ? sqrt(min(1, trebleRaw / tracking.trebleMax)) : 0,
            rms: isActive ? min(1, rmsRaw / tracking.rmsMax) : 0,
            beat: 0,
            isActive: isActive
        )

        // 비트: 저역 에너지가 이동 평균을 크게 넘으면 온셋.
        tracking.bassAvg = tracking.bassAvg * 0.92 + bassRaw * 0.08
        var beat = tracking.smoothed.beat * pow(0.02, dt / 0.35)
        if isActive,
           bassRaw > tracking.bassAvg * 1.6,
           bassRaw > tracking.bassMax * 0.35,
           tracking.clock - tracking.lastBeatTime > 0.22 {
            tracking.lastBeatTime = tracking.clock
            beat = 1
        }
        target.beat = beat

        // 어택 빠르게, 릴리즈 느리게.
        func smooth(_ prev: Float, _ next: Float) -> Float {
            let coefficient: Float = next > prev ? 0.55 : 0.18
            return prev + (next - prev) * coefficient
        }
        let previous = tracking.smoothed
        let smoothed = AudioLevels(bass: smooth(previous.bass, target.bass),
                                   mid: smooth(previous.mid, target.mid),
                                   treble: smooth(previous.treble, target.treble),
                                   rms: smooth(previous.rms, target.rms),
                                   beat: beat,
                                   isActive: isActive)
        tracking.smoothed = smoothed
        published.withLock { $0.levels = smoothed }
    }

    private func bandPower(lowHz: Float, highHz: Float, binHz: Float) -> Float {
        let lo = max(1, Int(lowHz / binHz))
        let hi = min(n / 2 - 1, Int(highHz / binHz))
        guard hi > lo else { return 0 }
        var sum: Float = 0
        for i in lo...hi {
            sum += magnitudes[i]
        }
        return sum / Float(hi - lo + 1)
    }
}
