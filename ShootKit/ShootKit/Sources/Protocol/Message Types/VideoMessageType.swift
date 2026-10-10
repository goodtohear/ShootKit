//
//  VideoMessageType.swift
//  ShootKit
//
//  Created by Michael Forrest on 02/06/2023.
//

import Foundation
import CoreMedia

enum VideoMessageType: UInt32 {
    case invalid = 0
    case videoFrame = 2
    case hevcParameterSet = 3
    case requestVideoStream = 4
    case cancelVideoStream = 5
    case cameraAvailable = 6
    case handshake = 7
    case clock = 8
    case control = 9
//    case version = 10
    case beatSheetAvailable = 11
    case streamDeckAvailable = 12
    case videoFrameWithHeader = 17 // 4-byte header length, JSON VideoFrameHeader, then the compressed frame
    case capabilities = 18 // JSON PeerCapabilities, sent by both ends after the existing handshake
}

/// What this end of the connection is able to receive.
/// Every field is optional so that more can be added later without breaking older peers.
struct PeerCapabilities: Codable {
    /// True if this peer can decode `videoFrameWithHeader` messages.
    var acceptsVideoFrameHeaders: Bool?
}

struct VideoFrameHeader: Codable {
    let presentationTimeStamp: CMTime
    let decodeTimeStamp: CMTime?
    let duration: CMTime?

    /// Builds a videoFrameWithHeader message body: header length, JSON header, compressed frame.
    static func payload(compressedVideoFrame: Data, presentationTimeStamp: CMTime) throws -> Data {
        let header = VideoFrameHeader(presentationTimeStamp: presentationTimeStamp, decodeTimeStamp: nil, duration: nil)
        let headerData = try JSONEncoder().encode(header)
        var headerLength = UInt32(headerData.count).littleEndian
        var payload = Data(capacity: MemoryLayout<UInt32>.size + headerData.count + compressedVideoFrame.count)
        withUnsafeBytes(of: &headerLength) { payload.append(contentsOf: $0) }
        payload.append(headerData)
        payload.append(compressedVideoFrame)
        return payload
    }
}

struct H265ParameterSet:Codable{
    let parameters: [Data]
}
