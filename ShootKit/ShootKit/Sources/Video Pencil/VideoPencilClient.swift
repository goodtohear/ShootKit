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
import CoreImage

@objc public protocol VideoPencilClientDelegate: AnyObject{
    func videoPencilDidConnect(_ client: VideoPencilClient)
    func videoPencilDidDisconnect(_ client: VideoPencilClient)
    func videoPencilDidReceive(from: VideoPencilClient, frame: CIImage, presentationTimeStamp: CMTime, presentationDuration: CMTime)
}

@objc public class VideoPencilClient: NSObject, ObservableObject{
    public var logger = BaseConnectionLogger()
    
    @objc public var name: String
    @objc public var size: CGSize
    
    @Published var hasReceivedControlMessage = false
    @Published var mostRecentVideoSelection: String?
    @Published var latestCompressedSampleBuffer: CMSampleBuffer?
    @Published var encoderBitRate: Int32 = 1920 * 1000
    
    var ciContext: CIContext
    var referencePixelBuffer: CVPixelBuffer?
    var scaledReferencePixelBuffer: CVPixelBuffer?
    
    var encoder: H265Encoder?
    
    private let queue: DispatchQueue
    
    @Published var connection: NWConnection? // not visible outside ShootKit but this will trigger an objectWillChange.send() so that hasConnection will work
    
    let bonjourBrowser = ShootKit.nwBrowser(for: .videoPencilApp)
    
    var hasSentParameterSet = false
    
    public var hasConnection: Bool{
        connection != nil
    }
    
    weak var delegate: VideoPencilClientDelegate?
    
    @objc public init(name: String, size: CGSize, delegate: VideoPencilClientDelegate, queue: DispatchQueue, ciContext: CIContext?=nil){
        self.name = name
        self.size = size
        self.delegate = delegate
        self.queue = queue
        self.ciContext = ciContext ?? CIContext()
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
            capabilitiesReceivedFromPeer = nil // the next connection may be to a different version
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
        queue.async {
            self.connection = connection // eesh
        }
        awaitNextMessage()
    }
    func handleConnectionStateChanges(newState: NWConnection.State){
        guard let connection = connection else { return }
        switch(newState){
        case .ready:
            log(message: "Video Pencil connection ready, awaiting message", color: .systemMint)
            if let data = try? JSONEncoder().encode(PeerCapabilities(acceptsVideoFrameHeaders: true)) {
                let message = NWProtocolFramer.Message(videoMessageType: .capabilities)
                let context = NWConnection.ContentContext(identifier: "capabilities", metadata: [message])
                connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
            }
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
            stopPacing()
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
        encoder = H265Encoder(width: 1920, height: 1080, bitRate: encoderBitRate, fps: 30, callbackQueue: queue)
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
                case .videoFrameWithHeader:
                    self.createDecoderIfNeeded()
                    self.decoder?.decodeFrameWithHeader(frame)
                case .capabilities:
                    self.capabilitiesReceivedFromPeer = try? JSONDecoder().decode(PeerCapabilities.self, from: frame)
                    
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
    
    /// What Video Pencil has told us it can receive. Nil until its capabilities message arrives.
    var capabilitiesReceivedFromPeer: PeerCapabilities?
    var decoder: H265Decoder?

    /// Drawing frames are handed to the delegate evenly, each at its display time (a few
    /// hundredths of a second after it was drawn), rather than the moment they decode: the
    /// network delivers them in bunches, which made the drawing look jerky. Turn off to get each
    /// frame as soon as it's decoded and pace them yourself
    @objc public var pacesReceivedFrames = true
    let frameSchedule = DecodedFrameSchedule<CVPixelBuffer>()
    var pacingTimer: DispatchSourceTimer?
    static let pacingRate = 60
    func createDecoderIfNeeded(){
        if decoder == nil {
            decoder = H265Decoder(width: 1920, height: 1080, callbackQueue: queue)
            decoder?.delegate = self
        }
    }
    func decode(frame: Data){
        createDecoderIfNeeded()
        decoder?.decode(frame)
    }
    @objc enum RenderError: Int, Error{
        case formatDescriptionUnavailable
        case sampleBufferNotCreated
    }
    @objc public func sendFrame(_ image: CIImage, presentationTimeStamp: CMTime, presentationDuration: CMTime) throws{
        guard let connection = connection,
              let encoder = encoder,
              connection.state == .ready
        else { return }
        
        var pixelBuffer: CVPixelBuffer?
        let minDimension = min(image.extent.height, image.extent.width)
        if minDimension > 1080{
            // scale it down
            let scale = 1080 / minDimension
            let scaled = image.transformed(by: .init(scaleX: scale, y: scale))
            if let current = scaledReferencePixelBuffer, CVPixelBufferGetWidth(current) == Int(image.extent.width), CVPixelBufferGetHeight(current) == Int(image.extent.height){
                
            }else{
                scaledReferencePixelBuffer = CIImage.createPixelBuffer(width: Int(scaled.extent.width), height: Int(scaled.extent.height))
            }
            if let scaledReferencePixelBuffer{
                ciContext.render(scaled, to: scaledReferencePixelBuffer)
            }
            pixelBuffer = scaledReferencePixelBuffer
            
        }else{
            if let b = image.pixelBuffer{
                pixelBuffer = b
            }else{
                if referencePixelBuffer == nil || CVPixelBufferGetWidth(referencePixelBuffer!) != Int(image.extent.width) || CVPixelBufferGetHeight(referencePixelBuffer!) != Int(image.extent.height){
                    referencePixelBuffer = CIImage.createPixelBuffer(width: Int(image.extent.width), height: Int(image.extent.height))
                }
                if let referencePixelBuffer{
                    ciContext.render(image, to: referencePixelBuffer)
                    pixelBuffer = referencePixelBuffer
                }
            }
        }
        guard let pixelBuffer  else { return }
        encoder.encode(pixelBuffer: pixelBuffer, presentationTimeStamp: presentationTimeStamp, duration: presentationDuration)
        
    }
    
    public func stop(){
        connection?.cancel()
        connection = nil
        encoder = nil
        decoder = nil
        stopPacing()
    }
}

extension CIImage{
    static func createPixelBuffer(width: Int, height: Int)->CVPixelBuffer?{
        guard width > 0 && height > 0 else { return nil }
        
        var copiedBuffer: CVPixelBuffer?
        
        let pixelFormat = kCVPixelFormatType_32BGRA //CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        let attrs: [CFString: Any] = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        
        CVPixelBufferCreate(
            nil,
            width,
            height,
            pixelFormat,
            attrs as CFDictionary,
            &copiedBuffer
        )
        
        return copiedBuffer
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
    func videoEncoderDidYieldVideoData(_ encoder: H265Encoder, compressedVideo data: Data, presentationTimeStamp: CMTime) {
        guard let connection = connection, hasSentParameterSet else {
            log("VideoPencilClient Ignoring frame, no keyframe received yet", color: .orange)
            return
        }
        guard data.underestimatedCount > 0 else {
            log(message: "Skipped sending nil data", color: .yellow)
            return
        }
        let packetSize = connection.maximumDatagramSize - 40
        guard packetSize > 0 else { return }
        
        var payload = data
        var messageType = VideoMessageType.videoFrame
        // Plain frames unless the peer has said it accepts headers: older versions ignore message type 17.
        if capabilitiesReceivedFromPeer?.acceptsVideoFrameHeaders == true,
           let payloadWithHeader = try? VideoFrameHeader.payload(compressedVideoFrame: data, presentationTimeStamp: presentationTimeStamp) {
            payload = payloadWithHeader
            messageType = .videoFrameWithHeader
        }
        let message = NWProtocolFramer.Message(videoMessageType: messageType)
        let context = NWConnection.ContentContext(identifier: "videoFrame", metadata: [message])
//        log(message: "Sending everything in one go", color: .systemGreen)
        connection.send(content: payload, contentContext: context, isComplete: true, completion: .contentProcessed({ [weak self] error in
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
    
    // on `queue`
    func videoDecoderDidDecodePixelBuffer(_ decoder: H265Decoder, pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, presentationDuration: CMTime) {
        // Timed frames (Video Pencil 2.1 and later) carry their display time on this Mac's host
        // clock: they wait for it. Untimed ones, from older versions, go straight out
        guard pacesReceivedFrames, presentationTimeStamp.isValid else {
            deliver(pixelBuffer, presentationTimeStamp: presentationTimeStamp, presentationDuration: presentationDuration)
            return
        }
        frameSchedule.add(pixelBuffer, displayTime: presentationTimeStamp, duration: presentationDuration)
        startPacingIfNeeded()
    }

    private func deliver(_ pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, presentationDuration: CMTime) {
        delegate?.videoPencilDidReceive(from: self, frame: CIImage(cvPixelBuffer: pixelBuffer), presentationTimeStamp: presentationTimeStamp, presentationDuration: presentationDuration)
    }

    /// Ticks at 60 a second and hands on whichever frame is due, so frames go out as evenly as
    /// they were drawn (they arrive bunched by the network and the decoder)
    private func startPacingIfNeeded() {
        guard pacingTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(Int(1_000_000_000 / Self.pacingRate)), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.deliverDueFrame()
        }
        pacingTimer = timer
        timer.resume()
    }

    private func deliverDueFrame() {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let refreshInterval = CMTime(value: 1, timescale: CMTimeScale(Self.pacingRate))
        guard let due = frameSchedule.takeFrameToShow(atRefreshTime: now, refreshInterval: refreshInterval) else { return }
        deliver(due.frame, presentationTimeStamp: due.displayTime, presentationDuration: due.duration)
    }

    func stopPacing() {
        queue.async { [self] in
            pacingTimer?.cancel()
            pacingTimer = nil
            frameSchedule.removeAll()
        }
    }
    
    func videoDecoder(_ decoder: H265Decoder, failedWith error: OSStatus) {
        // handle error
    }
}
