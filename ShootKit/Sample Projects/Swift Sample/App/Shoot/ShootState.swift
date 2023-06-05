//
//  ShootState.swift
//  Swift Sample
//
//  Created by Michael Forrest on 02/06/2023.
//

import Foundation
import ShootKit
import AVKit

class ShootState: ObservableObject{
    
    var shootServer: ShootServer?
    
    @Published var shootCameras = Set<ShootCamera>()
    
    init(){
        shootServer = ShootServer(name: "ShootKit Sample", delegate: self)
    }
}

extension ShootState: ShootServerDelegate{
 
    
    func shootServerDidDiscover(camera: ShootKit.ShootCamera) {
        DispatchQueue.main.async {
            self.shootCameras.insert(camera)
        }
    }
    
    func shootServerWasDisconnected(from camera: ShootKit.ShootCamera) {
        DispatchQueue.main.async {
            self.shootCameras.remove(camera)
        }
    }
    var shootCameraShouldCreateSampleBuffers: Bool { true }
    
    func shootCameraWasIdentified(camera: ShootKit.ShootCamera) { }
    
    func shootCameraWasDisconnected(camera: ShootKit.ShootCamera) { }
    
    func shootCamera(camera: ShootKit.ShootCamera, didReceiveSampleBuffer sampleBuffer: CMSampleBuffer) { }
    
    func shootCamera(camera: ShootKit.ShootCamera, didReceivePixelBuffer pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, presentationDuration: CMTime) { }
    
}
