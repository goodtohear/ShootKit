//
//  CameraSource.swift
//  ShootKit
//
//  Created by Michael Forrest on 02/06/2023.
//

import Foundation
import AVKit

class CameraSource: ObservableObject{
    var availableDevices: [AVCaptureDevice] = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .externalUnknown], mediaType: .video, position: .unspecified).devices
    
    @Published var selectedCamera: AVCaptureDevice?{
        didSet{
            if let device = selectedCamera{
                try? connectCamera(device: device)
            }
        }
    }
    
    let output = AVCaptureVideoDataOutput()
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "camera", qos: .userInteractive)
    
    init(captureDelegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        buildCaptureSession(captureDelegate: captureDelegate)
        selectedCamera = availableDevices.first
    }
    
    func buildCaptureSession(captureDelegate: AVCaptureVideoDataOutputSampleBufferDelegate){
        session.beginConfiguration()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(captureDelegate, queue: queue)
        session.addOutput(output)
      
        session.commitConfiguration()
      
    }
    func connectCamera(device: AVCaptureDevice) throws{
        let input = try AVCaptureDeviceInput(device: device)
        session.stopRunning()
        session.beginConfiguration()
        for input in session.inputs{
            session.removeInput(input)
        }
        session.addInput(input)
        session.commitConfiguration()
        session.startRunning()
    }
}
