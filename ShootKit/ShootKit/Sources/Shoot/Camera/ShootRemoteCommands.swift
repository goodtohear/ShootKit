//
//  VideoSourceProxy.swift
//  ShootWatchApp Extension
//
//  Created by Michael Forrest on 14/10/2020.
//  Copyright © 2020 Michael Forrest. All rights reserved.
//

import Foundation

import CoreMedia

public struct VideoSourceProxy: Identifiable, Hashable, Codable{
    public var id: String
    public var title: String
    public var iconName: String
}

public struct ShootSettings: Codable{
    public struct FaceFollow: Codable{
        var enabled: Bool
        var scale: Float
        var rate: Float
        var minScale: Float = 0
        var maxScale: Float = 0.3
        var minRate: Float = 0.00001
        var maxRate: Float = 0.5
        var scaleRange: ClosedRange<Float>{
            minScale...maxScale
        }
        var rateRange: ClosedRange<Float>{
            minRate...maxRate
        }
    }
    public enum GridMode:String,Codable{
        case threeByThree,sixByFour,threeByThreeWithDiagonal,square,fenwick
    }
    public var grid: GridMode?
    public var faceFollow: FaceFollow?
    public var gridOnDeviceOnly: Bool
}

public protocol SliderValueType:Codable,Hashable{
    var toFloat: Float { get }
    var conciseString: String { get }
    init(fromFloat: Float)
}
enum ControlValueOrigin:String,Codable{
    case `default` = "default"
    case device = "device"
    case watch = "watch"
    case slider = "slider"
    case preset = "preset"
    case pinch = "pinch"
    case squaresTV = "squares-tv"
    case current = "current"
    case videoPencilCamera = "video-pencil-camera"
    case beatSheetStudio = "beat-sheet-studio"
    
    var togglesAuto:Bool{
        switch self{
        case .default, .device: return false
        default: return true
        }
    }
}

public struct ControlValue<T:SliderValueType>:Codable{
    let value: T
    let origin: ControlValueOrigin
    init(_ value: T, origin: ControlValueOrigin){
        self.value = value
        self.origin = origin
    }
    func with(origin: ControlValueOrigin)->ControlValue{
        ControlValue(self.value, origin: origin)
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let floatValue = try container.decode(Float.self, forKey: .value)
        self.value = T(fromFloat: floatValue)
        self.origin = try container.decode(ControlValueOrigin.self, forKey: .origin)
    }
    enum CodingKeys: String, CodingKey{
        case value
        case origin
    }
}
extension ControlValue:Hashable{
    public static func == (lhs: ControlValue<T>, rhs: ControlValue<T>) -> Bool {
        lhs.value == rhs.value
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}
extension Float:SliderValueType{
    public var conciseString: String { String(format: "%1.3f", self) }
    public var toFloat: Float { self }
    public init(fromFloat: Float) {
        self.init(fromFloat)
    }
}
extension CGFloat:SliderValueType{
    public var conciseString: String { String(format: "%1.3f", self) }
    public var toFloat: Float { Float(self) }
    public init(fromFloat: Float) {
        self.init(fromFloat)
    }
}
extension CMTime:SliderValueType{
    public var toFloat: Float { Float(seconds) }
    public var conciseString: String { seconds > 0 ? "1/\(Int(1/seconds))" : "0" }
    public init(fromFloat: Float ) {
        self.init(seconds: Double(fromFloat), preferredTimescale: 16000)
    }
}

public enum CameraControl: String, Codable, Hashable{
    case zoom = "zoom"
    case ev = "ev"
    case focus = "focus"
    case iso = "exposure"
    case shutterSpeed = "shutter-speed"
    case whiteBalance = "white-balance"
    case torch = "torch"
    case tint = "tint"
    case blurRadius = "blur-radius"
    case gamma = "gamma"
    var key: String{
        rawValue
    }
    var autoKey: String{
        "auto-" + rawValue
    }
    var shortName: String{
        switch self{
        case .zoom: return "ZOOM"
        case .ev: return "EV"
        case .focus: return "FOCUS"
        case .iso: return "ISO"
        case .shutterSpeed: return "S"
        case .whiteBalance: return "WB"
        case .tint: return "TINT"
        case .torch: return "LIGHT"
        case .blurRadius: return "BLUR"
        case .gamma: return "GAMMA"
        }
    }
    var mediumName: String{
        switch self{
        case .shutterSpeed: return "SHUTTER"
        default: return shortName
        }
    }
    func format<T:SliderValueType>(_ value: T)-> String{
        switch self{
        case .whiteBalance: return "\(Int(value.toFloat))K"
        case .ev: return "\(value.toFloat >= 0 ? "+" : "")\(String(format: "%0.1f", value.toFloat)) ev"
        case .iso: return "ISO \(Int(value.toFloat))"
        case .shutterSpeed: return "\(value.conciseString) s"
        case .zoom: return "z \(String(format: "%1.1f", value.toFloat))"
        case .torch: return "🔦 \(String(format: "%1.1f", value.toFloat))"
        default: return value.conciseString
        }
    }
    static var order:[CameraControl] = [.zoom, .ev, .iso, .shutterSpeed, .whiteBalance, .torch]
    
}

extension CameraControl:Identifiable{
   public var id: String { self.rawValue }
}

public struct VideoSourceControlProxy: Identifiable, Codable{
    public var id: String
    public var title: String
    public var value: Float
    public var max: Float
    public var min: Float
    public var auto: Bool
    public var scale: SliderScaleProxy
}

public struct SliderScaleProxy: Codable{
    var minorTickValues: [Float]
    var majorTickValues: [Float]
    var isDiscrete: Bool
    init(sliderScale: SliderScale){
        minorTickValues = sliderScale.tickValues.filter{ sliderScale.isMajorTick(value: $0) == false}
        majorTickValues = sliderScale.tickValues.filter{ sliderScale.isMajorTick(value: $0) == true}
        isDiscrete = sliderScale.isDiscrete
    }
}


let VideoSourceControlChangeMessageKey = "control-value-changed"
public struct VideoSourceControlChange<T>: Identifiable, Codable where T: SliderValueType{
    public struct JSON: Codable{
        var control: CameraControl
        var value: ControlValue<Float>
        init<T:SliderValueType>(control: CameraControl, value: ControlValue<T>){
            self.control = control
            self.value = ControlValue(value.value.toFloat, origin: value.origin)
        }
    }
    
    static func currentValue(for control: CameraControl, value: Float )->[String:String]?{
        if let data = try? JSONEncoder().encode(
            VideoSourceControlChange<Float>(id: control.key, value: ControlValue(value, origin: .current))
        ){
            return [
                "message-key": control.id,
                VideoSourceControlChangeMessageKey: String(
                    data: data,
                    encoding: .utf8
                )!
            ]
        }else{
            return nil
        }
    }
    static func message(for id: String, value: T, origin: ControlValueOrigin)->[String:Data]{
        [
            "message-key": id.data(using: .utf8)!,
            VideoSourceControlChangeMessageKey: (try? JSONEncoder().encode(VideoSourceControlChange(id: id, value: ControlValue(value, origin: origin)))) ?? "".data(using: .utf8)!
        ]
    }
    public var id: String
    public var value: ControlValue<T>
}

public struct VideoSourceControlToggle: Identifiable, Codable{
    static let messageId = "control-value-toggled"
    static func message(for id: String, value: Bool)->[String:Data]{
        [
            "message-key": id.data(using: .utf8)!,
            messageId: try! JSONEncoder().encode(VideoSourceControlToggle(id: id, value: value))
        ]
    }
    
    static func currentValue(for control: CameraControl, value: Bool)->[String:String]{
        [
            "message-key": control.id,
            messageId: String(
                data: try! JSONEncoder().encode(
                    VideoSourceControlToggle(id: control.autoKey, value: value) // FIXME: THIS NEEDS TO ENCODE THE ORIGIN AT SOME POINT
                ),
                encoding: .utf8
            )!
        ]
    }
    public var id: String
    public var value: Bool
}
