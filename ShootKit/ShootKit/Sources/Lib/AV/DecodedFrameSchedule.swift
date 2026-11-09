//
//  DecodedFrameSchedule.swift
//  ShootKit
//
//  The same schedule CueCam uses for Shoot and Video Pencil frames.
//

import Foundation
import CoreMedia

/// Holds decoded frames until the display is ready for them.
/// Frames that arrive with a timestamp are chosen by display time, not handed out as they decode,
/// so the network's jitter doesn't reach the picture.
final class DecodedFrameSchedule<Frame> {
    struct ScheduledFrame {
        let frame: Frame
        /// Host-clock time at which this frame should first appear. Invalid means "as soon as possible".
        let displayTime: CMTime
        let duration: CMTime
    }

    private let lock = NSLock()
    private var framesWaitingForDisplay: [ScheduledFrame] = []   // oldest first
    /// Safety valve. In normal running only playoutDelay × frame rate frames are waiting (two or three).
    private let maximumFramesWaiting = 12

    /// Call when a frame has been decoded, on whatever thread that happens.
    func add(_ frame: Frame, displayTime: CMTime, duration: CMTime) {
        lock.lock(); defer { lock.unlock() }
        framesWaitingForDisplay.append(ScheduledFrame(frame: frame, displayTime: displayTime, duration: duration))
        if framesWaitingForDisplay.count > maximumFramesWaiting {
            framesWaitingForDisplay.removeFirst()
        }
    }

    /// Call once per refresh.
    /// Returns the frame to show, or nil if the frame already showing should stay.
    func takeFrameToShow(atRefreshTime refreshTime: CMTime, refreshInterval: CMTime) -> ScheduledFrame? {
        lock.lock(); defer { lock.unlock() }
        // A frame is due if this refresh is the one closest to its display time.
        let halfRefreshInterval = CMTimeMultiplyByRatio(refreshInterval, multiplier: 1, divisor: 2)
        let latestDisplayTimeConsideredDue = refreshTime + halfRefreshInterval
        let numberOfDueFrames = framesWaitingForDisplay.prefix {
            !$0.displayTime.isValid || $0.displayTime <= latestDisplayTimeConsideredDue
        }.count
        guard numberOfDueFrames > 0 else { return nil }
        let newestDueFrame = framesWaitingForDisplay[numberOfDueFrames - 1]
        // Removing every due frame is what drops the older late ones and prevents a backlog.
        framesWaitingForDisplay.removeFirst(numberOfDueFrames)
        return newestDueFrame
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        framesWaitingForDisplay.removeAll(keepingCapacity: true)
    }
}
