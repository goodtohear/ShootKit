//
//  SampleBufferPlayer.swift
//  Video Pencil Camera
//
//  Created by Michael Forrest on 08/12/2022.
//

import SwiftUI
import AVKit

class SampleBufferDisplayView: NSView{
    override func makeBackingLayer() -> CALayer {
        AVSampleBufferDisplayLayer()
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    var sampleBufferLayer: AVSampleBufferDisplayLayer{
        layer as! AVSampleBufferDisplayLayer
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

protocol SampleBufferSource{
    var latestSampleBuffer: CMSampleBuffer? { get }
}

struct SampleBufferPlayer: NSViewRepresentable{
    typealias NSViewType = SampleBufferDisplayView
    var sampleBufferSource: SampleBufferSource

    func makeNSView(context: Context) -> SampleBufferDisplayView {
        let view = SampleBufferDisplayView()
        view.sampleBufferLayer.requestMediaDataWhenReady(on: .main) {
            if view.sampleBufferLayer.isReadyForMoreMediaData, let sampleBuffer = sampleBufferSource.latestSampleBuffer{
                view.sampleBufferLayer.enqueue(sampleBuffer)
            }
        }
        return view
    }
    func updateNSView(_ view: SampleBufferDisplayView, context: Context) {
    }
}

