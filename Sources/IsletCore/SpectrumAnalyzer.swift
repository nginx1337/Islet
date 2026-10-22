import Accelerate
import Foundation

/// Turns audio samples into four bar heights: bass, low mids, mids, highs.
///
/// 1024-point FFT every 512 samples (≈ 94 times a second at 48 kHz). The bands share one adaptive
/// reference level, so loud and quiet passages both move the bars, and a bass-heavy beat shows
/// as a tall first bar rather than lifting every bar. Not thread-safe: call from one queue.
public final class SpectrumAnalyzer: @unchecked Sendable {
    /// Band edges in Hz: bass, low mids, mids, highs.
    public static let bands: [ClosedRange<Double>] = [35...160, 160...700, 700...2800, 2800...10000]
    /// Music has less energy up high; this tilt (dB) keeps the upper bars alive.
    static let tilt: [Float] = [0, 5, 10, 16]
    /// Loudness range mapped onto a bar, in dB.
    static let range: Float = 34
    static let floorDB: Float = -60

    public static let fftSize = 1024
    public static let hop = 512

    public let sampleRate: Double
    /// Smoothed bar heights, 0…1.
    public private(set) var levels: [Float] = [0, 0, 0, 0]
    /// Whether the last analysed block had any sound.
    public private(set) var hasSignal = false
    /// Whether any sound was seen since this analyzer was created
    /// (all-zero input means system audio capture is not allowed).
    public private(set) var signalSeen = false

    private let log2n = vDSP_Length(10)
    private let setup: FFTSetup
    private var window: [Float]
    private var ring: [Float]
    private var writeIndex = 0
    private var pending = 0
    private var reference: Float = SpectrumAnalyzer.floorDB
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    private var frame: [Float]
    private let bandBins: [Range<Int>]

    public init(sampleRate: Double) {
        let n = Self.fftSize
        self.sampleRate = sampleRate > 0 ? sampleRate : 48_000
        setup = vDSP_create_fftsetup(vDSP_Length(10), FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        ring = [Float](repeating: 0, count: n)
        real = [Float](repeating: 0, count: n / 2)
        imag = [Float](repeating: 0, count: n / 2)
        magnitudes = [Float](repeating: 0, count: n / 2)
        frame = [Float](repeating: 0, count: n)
        let binWidth = self.sampleRate / Double(n)
        bandBins = Self.bands.map { band in
            let lo = max(1, Int((band.lowerBound / binWidth).rounded(.down)))
            let hi = min(n / 2, max(lo + 1, Int((band.upperBound / binWidth).rounded(.up))))
            return lo..<hi
        }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Feeds mono samples. Returns true when the levels were updated.
    @discardableResult
    public func process(_ samples: UnsafeBufferPointer<Float>) -> Bool {
        var updated = false
        let n = Self.fftSize
        for sample in samples {
            ring[writeIndex] = sample
            writeIndex = (writeIndex + 1) % n
            pending += 1
            if pending >= Self.hop {
                pending = 0
                analyse()
                updated = true
            }
        }
        return updated
    }

    @discardableResult
    public func process(_ samples: [Float]) -> Bool {
        samples.withUnsafeBufferPointer { process($0) }
    }

    private func analyse() {
        let n = Self.fftSize
        // Oldest sample first.
        for i in 0..<n { frame[i] = ring[(writeIndex + i) % n] }
        var peak: Float = 0
        vDSP_maxmgv(frame, 1, &peak, vDSP_Length(n))
        hasSignal = peak > 1e-4
        if hasSignal { signalSeen = true }
        vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(n))

        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                split.imagp[0] = 0 // packed Nyquist value, not part of bin 0
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
            }
        }

        // Mean power per band, in dB, with the tilt applied.
        let scale = 1 / Float(n * n)
        var bandDB = [Float](repeating: Self.floorDB, count: bandBins.count)
        for (b, bins) in bandBins.enumerated() {
            var sum: Float = 0
            for i in bins { sum += magnitudes[i] }
            let power = sum / Float(bins.count) * scale
            bandDB[b] = 10 * log10(power + 1e-20) + Self.tilt[b]
        }

        // Shared reference: jumps up to the loudest band, sinks slowly (≈ 6 dB/s).
        let loudest = bandDB.max() ?? Self.floorDB
        reference = max(Self.floorDB, max(loudest, reference - 0.065))

        for b in 0..<levels.count {
            let target = hasSignal ? min(1, max(0, (bandDB[b] - (reference - Self.range)) / Self.range)) : 0
            let speed: Float = target > levels[b] ? 0.55 : 0.2
            levels[b] += (target - levels[b]) * speed
        }
    }
}
