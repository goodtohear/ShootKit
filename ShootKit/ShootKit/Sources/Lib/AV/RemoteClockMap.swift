//
//  RemoteClockMap.swift
//  ShootKit
//
//  Created by Michael Forrest / LLM on 10/10/2026.
//
import CoreMedia
final class RemoteClockMap {
    /// How long after its mapped capture time each frame is shown.
    /// Must exceed keyframe transit time plus network jitter.
    var playoutDelay: TimeInterval = 0.070

    /// Enough to span several keyframe intervals, so the window always contains some quick frames.
    private let clockOffsetMeasurementsToKeep = 120
    /// The first frame is a slow keyframe, so trust the newest minimum outright until this many frames have arrived.
    private let warmUpFrameCount = 30
    /// The estimate may fall this fast when a quicker frame shows the offset was overestimated.
    private let maximumDecreasePerFrame: TimeInterval = 0.0003
    /// The estimate may rise only as fast as real clock drift (about 150 ppm at 30 fps).
    /// A standing backlog must show up as late frames, not be absorbed as a new offset.
    private let maximumIncreasePerFrame: TimeInterval = 0.000005

    /// One measurement per recent frame of how far the receiver's clock is ahead of the sender's.
    /// Each is too large by however long that frame spent in transit, so the smallest is the most accurate.
    private var recentClockOffsetMeasurements: [TimeInterval] = []
    private var estimatedClockOffset: TimeInterval?

    /// Returns the receiver host-clock time at which the frame should be displayed.
    func displayHostTime(forSenderPresentationTimeStamp senderPresentationTimeStamp: CMTime,
                         arrivalHostTime: CMTime = CMClockGetTime(CMClockGetHostTimeClock())) -> CMTime {
        let clockOffsetMeasurement = arrivalHostTime.seconds - senderPresentationTimeStamp.seconds
        recentClockOffsetMeasurements.append(clockOffsetMeasurement)
        if recentClockOffsetMeasurements.count > clockOffsetMeasurementsToKeep {
            recentClockOffsetMeasurements.removeFirst()
        }

        // The smallest measurement came from the frame that spent least time in transit.
        let leastDelayedClockOffsetMeasurement = recentClockOffsetMeasurements.min()!

        let isWarmingUp = recentClockOffsetMeasurements.count < warmUpFrameCount
        let previousEstimate = estimatedClockOffset ?? leastDelayedClockOffsetMeasurement
        let updatedEstimate: TimeInterval
        if isWarmingUp {
            updatedEstimate = leastDelayedClockOffsetMeasurement
        } else {
            let desiredChange = leastDelayedClockOffsetMeasurement - previousEstimate
            let limitedChange = max(-maximumDecreasePerFrame,
                                           min(maximumIncreasePerFrame, desiredChange))
            updatedEstimate = previousEstimate + limitedChange
        }
        estimatedClockOffset = updatedEstimate

        let displayTime = senderPresentationTimeStamp.seconds + updatedEstimate + playoutDelay
        return CMTime(seconds: displayTime, preferredTimescale: 1_000_000_000)
    }
}
