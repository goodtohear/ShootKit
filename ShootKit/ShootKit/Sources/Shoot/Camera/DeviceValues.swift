//
//  DeviceValues.swift
//  Shoot
//
//  Created by Michael Forrest on 09/08/2022.
//  Copyright © 2022 Michael Forrest. All rights reserved.
//

import Foundation
import CoreMedia

struct DeviceValues: Codable{
    // WARNING: COPIED FROM CameraPreset
    // storing different types separately for automatic Codable conformance
    // but these are unordered dictionaries
    
    let values: [[String:String]]
    let auto: [[String:String]]

}
