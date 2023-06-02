//
//  CMTIme+Extensions.swift
//  TelestratorApp
//
//  Created by Michael Forrest on 23/02/2023.
//

import Foundation
import AVFoundation

extension CMTime: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.init()
        self.value = try container.decode(CMTimeValue.self, forKey: .value)
        self.timescale = try container.decode(CMTimeScale.self, forKey: .timescale)
        self.flags = CMTimeFlags(rawValue: try container.decode(UInt32.self, forKey: .flags))
        self.epoch = try container.decode(CMTimeEpoch.self, forKey: .epoch)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.value, forKey: .value)
        try container.encode(self.timescale, forKey: .timescale)
        try container.encode(self.flags.rawValue, forKey: .flags)
        try container.encode(self.epoch, forKey: .epoch)
    }
    
    private enum CodingKeys: String, CodingKey {
        case value
        case timescale
        case flags
        case epoch
    }
}
