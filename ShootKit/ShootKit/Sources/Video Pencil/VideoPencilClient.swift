//
//  VideoConnectionDesktopState.swift
//  Video Pencil Camera
//
//  Created by Michael Forrest on 07/12/2022.
//

import Foundation
import Network
import VideoToolbox
import AppKit

@objc public protocol VideoPencilClientDelegate: AnyObject{
    var videoPencilClientShouldCreateSampleBuffers: Bool { get }
    
    func videoPencilDidConnect(_ client: VideoPencilClient)
    func videoPencilDidDisconnect(_ client: VideoPencilClient)
    
    func videoPencilDidReceive(from: VideoPencilClient, pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, presentationDuration: CMTime)
    func videoPencilDidReceive(from: VideoPencilClient, sampleBuffer: CMSampleBuffer)
}

@objc public class VideoPencilClient: NSObject, ObservableObject{
    public var logger = BaseConnectionLogger()
    
    @objc public var name: String
    
    @Published var hasReceivedControlMessage = false
    @Published var mostRecentVideoSelection: String?
    @Published var latestCompressedSampleBuffer: CMSampleBuffer?
    @Published var encoderBitRate: Int32 = 1920 * 1000
    
    var encoder: H265Encoder?
    
    private let queue = DispatchQueue(label: "Video Pencil Client", qos: .userInitiated)
    
    @Published var connection: NWConnection? // not visible outside ShootKit but this will trigger an objectWillChange.send() so that hasConnection will work
    
    let bonjourBrowser = ShootKit.nwBrowser(for: .videoPencilApp)
    
    var hasSentParameterSet = false
    
    public var hasConnection: Bool{
        connection != nil
    }
    
    weak var delegate: VideoPencilClientDelegate?
    
    @objc public init(name: String, delegate: VideoPencilClientDelegate){
        self.name = name
        self.delegate = delegate
        super.init()
        startBonjourDiscovery()
    }
    
    func startBonjourDiscovery(){
        bonjourBrowser.browseResultsChangedHandler = {newResults, changes in // main thread
            self.log(message: "Bonjour results changed \(newResults.debugDescription)", color: NSColor.brown)

            if let connection = self.connection{
                let myEndpointDisappeared = !newResults.contains(where: {$0.endpoint == connection.endpoint})
                if myEndpointDisappeared{
                    // endpoint that was being used has disappeared
                    self.log(message: "Video Pencil endpoint disappeared, cancelling connection", color: .red)
                    self.connection?.cancel()
                    self.stop()
                }
            }else{
                if let result = newResults.first {
                    self.connectTo_iPad(at: result)
                }
            }
        }
        if let service = bonjourBrowser.browseResults.first{
            connectTo_iPad(at: service)
        }
        bonjourBrowser.start(queue: queue)
    }
    

    func start(){
        if let result = bonjourBrowser.browseResults.first{
            connectTo_iPad(at: result)
        }
    }
    
    func tryReconnecting(){
        stop()
        start()
    }

    private func connectTo_iPad(at networkBrowserResult: NWBrowser.Result){
        if connection != nil {
            log(message: "Removing existing Video Pencil connection", color: .systemOrange)
            connection?.cancel()
            decoder = nil
            encoder = nil
            connection = nil
        }
        log(message: "Attempt to connect to Video Pencil at \(networkBrowserResult) port \(networkBrowserResult.metadata)", color: .systemMint)
        let connection = NWConnection(to: networkBrowserResult.endpoint, using: ShootKit.applicationServiceParameters())

        connection.stateUpdateHandler = handleConnectionStateChanges
        
        connection.viabilityUpdateHandler = { isViable in
            if !isViable{
                self.log(message: "Connection viability lost, attempt reconnection", color: .systemRed)
                self.tryReconnecting()
            }
        }
        // send the device name with the initial connection
        connection.send(content: name.data(using: .unicode), completion: .idempotent)
        
        connection.start(queue: queue)
        self.connection = connection
        awaitNextMessage()
    }
    func handleConnectionStateChanges(newState: NWConnection.State){
        guard let connection = connection else { return }
        switch(newState){
        case .ready:
            log(message: "Video Pencil connection ready, awaiting message", color: .systemMint)
            DispatchQueue.main.async {
                self.delegate?.videoPencilDidConnect(self)
            }
            awaitNextMessage()
        case .failed(let error):
            log(message: "Video Pencil connection failed: " + error.localizedDescription, color: .systemRed)
            tryReconnecting()
        case .preparing:
            log(message: "Preparing connection to Video Pencil... \(connection.parameters)", color: .systemMint)
        case .waiting(let error):
            log(message: "Waiting for Video Pencil connection: \(error.localizedDescription)", color: .orange)
        case .cancelled:
            // guaranteed to be final
            log(message: "Video Pencil connection cancelled \(connection.endpoint.debugDescription)", color: .systemRed)
            DispatchQueue.main.async {
                self.connection = nil
                self.delegate?.videoPencilDidDisconnect(self)
            }
        default: // preparing
            log(message: "Video Pencil Connection state changed to \(newState)", color: .orange)
            break
        }
    }

    func startVideoStream(){
        hasSentParameterSet = false
        encoder = H265Encoder(width: 1920, height: 1080, bitRate: encoderBitRate, fps: 30)
        encoder?.delegate = self
    }
    
    func cancelVideoStream(){
        encoder = nil
    }
    
    func send<T>(basicMessage: BasicControlMessage<T>){
        guard let data = try? JSONEncoder().encode(basicMessage) else { return }
        let message = NWProtocolFramer.Message(videoMessageType: .control)
        let context = NWConnection.ContentContext(identifier: "control", metadata: [message])
        
        connection?.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                self?.log(message: "Error sending control message " + error.debugDescription, color: .red)
            }
        }))
            
        awaitNextMessage()
    }
    
    func awaitNextMessage(){
        connection?.receiveMessage(completion: { content, context, isComplete, error in
//            self.log(message: "Got message \(content)")
            if let message = context?.protocolMetadata(definition: VideoProtocol.definition) as? NWProtocolFramer.Message, let frame = content{
                switch message.videoMessageType{
                case .requestVideoStream:
                    self.cancelVideoStream()
                    self.log(message: "Video stream requested by Video Pencil", color: .systemOrange)
                    self.startVideoStream()
                    
                case .cancelVideoStream:
                    self.log(message: "Video stream cancelled by Video Pencil", color: .systemOrange)
                    self.cancelVideoStream()
                    
                case .hevcParameterSet:
                    if let parameterSet = try? JSONDecoder().decode(H265ParameterSet.self, from: frame){
                        self.log(message: "HEVC parameter set received from Video Pencil (\(parameterSet.parameters), decoder exists? \(self.decoder != nil))", color: .systemOrange)
                        // received pencil layer parameterSet
                        self.createDecoderIfNeeded()
                        
                        self.decoder?.parameterSet = parameterSet.parameters
                    }else{
                        self.log(message: "Error parsing HEVC parameter set from Video Pencil \(frame)", color: .systemRed)
                    }
                
                case .videoFrame:
                    // received pencil layer
                    self.decode(frame: frame)
                    
                case .invalid, .cameraAvailable, .handshake:
                    break
                default:
                    break // need to be careful about future messages breaking things!
                }
            }
            if let error = error {
                self.log(message: "Error receiving message \(error)", color: .red)
            }else{
                self.awaitNextMessage()
            }
        })
    }
    
    func send(controlMessage: VideoPencilControlMessage){
        let message = BasicControlMessage(command: controlMessage)
        send(basicMessage: message)
    }
    
    var decoder: H265Decoder?
    func createDecoderIfNeeded(){
        if decoder == nil {
            decoder = H265Decoder()
            decoder?.setConfig(width: 1920, height: 1080)
            decoder?.delegate = self
        }
    }
    func decode(frame: Data){
        createDecoderIfNeeded()
        decoder?.decode(frame)
    }
    
    @objc public func send(sampleBuffer: CMSampleBuffer){
        guard let connection = connection,
              let encoder = encoder,
              connection.state == .ready
        else { return }

        encoder.encode(sampleBuffer)
    }
    
    public func stop(){
        connection?.cancel()
        connection = nil
        encoder = nil
        decoder = nil
    }
}


extension VideoPencilClient: H265EncoderDelegate{
    func videoEncoderDidExtractParameterSet(_ encoder: H265Encoder, parameterSet frames: [Data]) {
        guard let connection = connection else { return }
        log(message: "Sending encoder parameters to Video Pencil: \(frames.map{$0})", color: .blue)
        
        let message = NWProtocolFramer.Message(videoMessageType: .hevcParameterSet)
        let context = NWConnection.ContentContext(identifier: "parameterSet", metadata: [message])
        let parameterSet = H265ParameterSet(parameters: frames)
        let data = try! JSONEncoder().encode(parameterSet)
        
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                self?.log(message: "Error sending frame " + error.debugDescription, color: .red)
            }else{
                self?.hasSentParameterSet = true
            }
        }))
    }
    func videoEncoderDidYieldVideoData(_ encoder: H265Encoder, compressedVideo data: Data) {
        guard let connection = connection, hasSentParameterSet else { return }
        guard data.underestimatedCount > 0 else {
            log(message: "Skipped sending nil data", color: .yellow)
            return
        }
        let packetSize = connection.maximumDatagramSize - 40
        guard packetSize > 0 else { return }
        
        let message = NWProtocolFramer.Message(videoMessageType: .videoFrame)
        let context = NWConnection.ContentContext(identifier: "videoFrame", metadata: [message])
//        log(message: "Sending everything in one go", color: .systemGreen)
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                self?.log(message: "Error sending encoded video:" + error.debugDescription, color: .red)

            }
        }))
    }
    func videoEncoderDidEncodeSampleBuffer(_ encoder: H265Encoder, sampleBuffer: CMSampleBuffer) {
    }
    func videoEncoderDidFail(_ encoder: H265Encoder, error: OSStatus) {
        if error == kVTInvalidSessionErr{
            self.encoder = nil
        }
    }
}

extension VideoPencilClient: ConnectionLogger{
    public func log(_ text: String, color: NSColor) {
        logger.log(text, color: color)
    }
    public func log(message: String, color: NSColor) {
        logger.log(message: message, color: color)
    }
}

extension VideoPencilClient: H265DecoderDelegate{
    var shouldCreateSampleBuffers: Bool {
        delegate?.videoPencilClientShouldCreateSampleBuffers ?? true
    }
    
    func videoDecoderDidDecodePixelBuffer(_ decoder: H265Decoder, pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, presentationDuration: CMTime) {
        delegate?.videoPencilDidReceive(from: self, pixelBuffer: pixelBuffer, presentationTimeStamp: presentationTimeStamp, presentationDuration: presentationDuration)
    }
    func videoDecoderDidDecodeSampleBuffer(_ decoder: H265Decoder, sampleBuffer: CMSampleBuffer) {
        DispatchQueue.main.async {
            self.delegate?.videoPencilDidReceive(from: self, sampleBuffer: sampleBuffer)
        }
    }
    func videoDecoder(_ decoder: H265Decoder, failedWith error: OSStatus) {
        
    }
}
