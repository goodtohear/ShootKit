//
//  Formatter+Extensions.swift
//  ShootKit
//
//  Created by Michael Forrest on 02/06/2023.
//

import Foundation

extension Formatter{
    static let intFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    static let floatFormatter: NumberFormatter = {
       let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    
}
