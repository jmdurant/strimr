import Foundation
import os

/// Thread-safe container for FFT spectrum magnitude bins.
/// Written from the VLC audio callback thread, read from the main thread for visualization.
/// Not @Observable — the TimelineView drives 30fps reads; no SwiftUI observation needed.
final class SpectrumData: NSObject, @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var _bins: [Float] = Array(repeating: 0, count: 32)

    /// Returns a snapshot copy of the current spectrum bins (lock-guarded).
    var bins: [Float] {
        os_unfair_lock_lock(&lock)
        let copy = _bins
        os_unfair_lock_unlock(&lock)
        return copy
    }

    /// Replaces the stored bins with new FFT output (lock-guarded).
    func update(_ newBins: [Float]) {
        os_unfair_lock_lock(&lock)
        let count = min(newBins.count, _bins.count)
        for i in 0..<count {
            _bins[i] = newBins[i]
        }
        os_unfair_lock_unlock(&lock)
    }

    /// Called from Objective-C (VLCAudioBridge) with an NSArray of NSNumber.
    /// Applies temporal smoothing: rise fast (0.6 blend), fall slow (0.15 blend)
    /// so visualizations feel responsive on hits but flow smoothly on decay.
    @objc func updateFromObjC(_ numbers: [NSNumber]) {
        os_unfair_lock_lock(&lock)
        let count = min(numbers.count, _bins.count)
        for i in 0..<count {
            let newVal = numbers[i].floatValue
            let current = _bins[i]
            if newVal > current {
                _bins[i] = current + (newVal - current) * 0.6
            } else {
                _bins[i] = current + (newVal - current) * 0.15
            }
        }
        os_unfair_lock_unlock(&lock)
    }

    /// Zeros out all bins (e.g. on pause / stop).
    func reset() {
        os_unfair_lock_lock(&lock)
        for i in 0..<_bins.count {
            _bins[i] = 0
        }
        os_unfair_lock_unlock(&lock)
    }
}
