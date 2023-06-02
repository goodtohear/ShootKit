//
//  ShootControlMessage.swift
//  ShootKit
//
//  Created by Michael Forrest on 02/06/2023.
//

import Foundation

enum ShootControlMessage: String, Codable{
    case availableControls // strings to VideoSourceControlProxy
    case availableSources // strings to VideoSourceProxy
    case currentValues // keyed to availableControls
    case currentAutoToggles // keyed to availableControls
    case settings // json to ShootSettings
    case controlChange
    case controlToggle
    case selectedSource
    case remoteDeviceIdentifier // used by squares.tv
}
