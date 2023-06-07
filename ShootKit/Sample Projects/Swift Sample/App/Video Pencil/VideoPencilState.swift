//
//  VideoPencilState.swift
//  ShootKit
//
//  Created by Michael Forrest on 02/06/2023.
//

import Foundation
import AVKit
import ShootKit


class VideoPencilState: NSObject, ObservableObject{
    @Published var isConnected = false
    
    var videoPencilClient: VideoPencilClient!
    var cameraSource: CameraSource!
    
    var videoPencilBuffers = BufferSource()
    var cameraBuffers = BufferSource()
    
    override init(){
        super.init()
        cameraSource = CameraSource(captureDelegate: self)
        videoPencilClient = VideoPencilClient(name: "Swift Sample", delegate: self)
    }
    
}

// Handle local camera output
extension VideoPencilState: AVCaptureVideoDataOutputSampleBufferDelegate{
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Keep a buffer to display in the demo
        cameraBuffers.latestSampleBuffer = sampleBuffer
        
        // Send to Video Pencil
        videoPencilClient.send(sampleBuffer: sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) { }
    
}

// Receive transparent frames from Video Pencil
extension VideoPencilState: VideoPencilClientDelegate{
    var videoPencilClientShouldCreateSampleBuffers: Bool {
        true // save extra processing work by setting this to false if you just want pixel buffers
    }
    func videoPencilDidReceive(from: VideoPencilClient, pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, presentationDuration: CMTime) {
        // We're using sample buffers for this demo but you can take the pixelBuffer instead by implementing this method.
    }
    func videoPencilDidReceive(from: VideoPencilClient, sampleBuffer: CMSampleBuffer) {
        videoPencilBuffers.latestSampleBuffer = sampleBuffer
    }
    func videoPencilDidConnect(_ client: VideoPencilClient) {
        DispatchQueue.main.async {
            self.isConnected = true
        }
    }
    func videoPencilDidDisconnect(_ client: VideoPencilClient) {
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}

// helper class to drive the SampleBufferPlayer
class BufferSource: SampleBufferSource{
    var latestSampleBuffer: CMSampleBuffer?
}
