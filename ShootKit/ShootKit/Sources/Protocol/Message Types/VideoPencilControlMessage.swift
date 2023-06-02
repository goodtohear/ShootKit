//
//  VideoPencilControlMessage.swift
//  ShootKit
//
//  Created by Michael Forrest on 02/06/2023.
//

import Foundation
enum VideoPencilControlMessage: String, Codable, CaseIterable{
    case clearDrawing = "spacebar"
    case selectToolByNumber = "select-tool"
    case selectEraseTool = "erase-tool"
    case selectLassoTool = "lasso-tool"
    case selectLaserPointer = "laser-pointer"
    case toggleLiveTitles = "toggle-live-titles"
    case selectLanguageByNumber = "select-language"
    case undoDrawing = "undo-drawing"
    case redoDrawing = "redo-drawing"
    case backwardOneFrame = "backward-one-frame"
    case togglePlayback = "toggle-playback"
    case forwardOneFrame = "forward-one-frame"
    
    var maxNumber: Int?{
        if hasArguments{
            switch self{
            case .selectToolByNumber: return 5
            case .selectLanguageByNumber: return 3
            default: break
            }
        }
        return nil
    }
    
    func basicMessage(components: [String])->BasicControlMessage<VideoPencilControlMessage>?{
        if hasArguments{
            if let number = Int(components[2]){
                return BasicControlMessage(command: self, intArguments: [number])
            }
        }else{
            return BasicControlMessage(command: self)
        }
        return nil
    }
    
    var hasArguments: Bool{
        switch self{
        case .selectToolByNumber, .selectLanguageByNumber:
            return true
        default:
            return false
        }
    }
    
    var title: String{
        switch self {
        case .clearDrawing:
            return "Clear Drawing"
        case .selectEraseTool:
            return "Select Erase Tool"
        case .selectToolByNumber:
            return "Select Pen"
        case .selectLassoTool:
            return "Select Lasso Tool"
        case .selectLaserPointer:
            return "Select Laser Pointer"
        case .toggleLiveTitles:
            return "Toggle Live Titles"
        case .selectLanguageByNumber:
            return "Select Live Titles Language"
        case .undoDrawing:
            return "Undo Drawing"
        case .redoDrawing:
            return "Redo Drawing"
        case .backwardOneFrame:
            return "Previous Frame"
        case .togglePlayback:
            return "Play/Pause"
        case .forwardOneFrame:
            return "Next Frame"
        }
    }
}
