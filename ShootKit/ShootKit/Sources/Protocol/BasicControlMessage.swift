//
//  BasicControlMessage.swift
//  ShootKit
//
//  Created by Michael Forrest on 02/06/2023.
//

import Foundation

struct BasicControlMessage<CommandType:Codable>: Codable{
    var command: CommandType
    var stringArguments: [String]? = nil
    var floatArguments: [Float]? = nil
    var intArguments: [Int]? = nil
    enum CodingKeys: CodingKey{
        case command, stringArguments, floatArguments, intArguments
    }
    init(command: CommandType, stringArguments: [String]?=nil, floatArguments: [Float]?=nil, intArguments: [Int]?=nil){
        self.command = command
        self.stringArguments = stringArguments
        self.floatArguments = floatArguments
        self.intArguments = intArguments
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.command = try container.decode(CommandType.self, forKey: .command)
        self.stringArguments = try container.decode([String]?.self, forKey: .stringArguments)
        self.floatArguments = try container.decode([Float]?.self, forKey: .floatArguments)
        self.intArguments = try container.decode([Int]?.self, forKey: .intArguments)
    }
        
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try? container.encode(command, forKey: .command)
        try? container.encode(stringArguments, forKey: .stringArguments)
        try? container.encode(floatArguments, forKey: .floatArguments)
        try? container.encode(intArguments, forKey: .intArguments)
    }
}
