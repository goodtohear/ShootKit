//
//  VideoMessageType.swift
//  ShootKit
//
//  Created by Michael Forrest on 02/06/2023.
//

import Foundation

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
}

struct H265ParameterSet:Codable{
    let parameters: [Data]
}
