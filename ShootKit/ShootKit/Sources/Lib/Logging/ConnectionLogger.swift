//
//  ConnectionLogger.swift
//  BeatSheet
//
//  Created by Michael Forrest on 25/05/2023.
//

import Foundation
import AppKit

public protocol ConnectionLogger{
    func log(_ text: String, color: NSColor)
    func log(message: String, color: NSColor)
}

public struct BaseConnectionLogger: ConnectionLogger{
    public func log(_ text: String, color: NSColor){
        print(color.emoji,text)
    }
    public func log(message: String, color: NSColor){
        log(message, color: color)
    }
}

extension NSColor{
    var emoji:String{
        switch self{
        case .systemGreen,.green: return "🟩"
        case .systemRed,.red: return "🟥"
        case .systemOrange,.orange: return "🟧"
        case .systemBlue,.blue: return "🟦"
        default: return ""
        }
    }
}
