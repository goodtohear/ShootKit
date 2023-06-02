//
//  ShootCamera.swift
//  TelestratorApp
//
//  Created by Michael Forrest on 29/01/2023.
//

import Foundation
import Network
import AppKit
import VideoToolbox

public protocol ShootCameraDelegate:AnyObject{
    func shootCameraWasIdentified(camera: ShootCamera) // we have the name
    func shootCameraWasDisconnected(camera: ShootCamera)
}

public class ShootCamera: ObservableObject, Identifiable{
   
    public var logger = BaseConnectionLogger()
    var connection: NWConnection
    weak var delegate: ShootCameraDelegate?
    public var id:String{ name }
    
    public var latestSampleBuffer: CMSampleBuffer?
    public var latestPixelBuffer: CVPixelBuffer?
//    var latestPixelBufferAsCGImage: CGImage?
        
    @Published public var isRunning = false
    
    @Published public var sources = [VideoSourceProxy]()
    @Published public var controls = [VideoSourceControlProxy]()
    @Published public var settings: ShootSettings?
    @Published public var values = [String:Float]()
    @Published public var autoValues = [String: Bool]()
    @Published public var selectedSource: VideoSourceProxy?
    
    @Published public var remoteDeviceIdentifier: String?
    

    
    @Published public var name = ""
    
    private let queue = DispatchQueue(label: "Shoot Connection Queue", qos: .userInitiated)

    
    var isDisconnected: Bool{
        switch connection.state{
        case .failed(_),.cancelled: return true
        default: return false
        }
    }
    
    init(connection: NWConnection, delegate: ShootCameraDelegate){
        self.connection = connection
        self.delegate = delegate
        connection.stateUpdateHandler = handleConnectionStateChanges
        connection.start(queue: queue)
        
        awaitNextMessage()
    }

    func handleConnectionStateChanges(newState: NWConnection.State){
        switch newState {
        case .setup:
            log("Setup Shoot connection", color: .systemBlue)
        case .waiting(let error):
            log("Waiting for Shoot connection -- \(error.debugDescription)", color: .systemBlue)
        case .preparing:
            log("Preparing Shoot connection", color: .systemBlue)
        case .ready:
            log("Shoot connection ready", color: .systemGreen)
            sendFramedMessage(data: "Hello".data(using: .utf8), id: "Hello", type: .handshake, idempotent: true)
            awaitNextMessage()
        case .failed(let error):
            log("Shoot connection failed -- \(error.debugDescription)", color: .systemRed)
            decoder = nil
            delegate?.shootCameraWasDisconnected(camera: self)
        case .cancelled:
            // guaranteed to be final
            log("Shoot connection failed", color: .systemRed)
            decoder = nil
            delegate?.shootCameraWasDisconnected(camera: self)
        default:
            break
        }
    }
    func sendFramedMessage(data: Data?, id: String, type: VideoMessageType, idempotent: Bool=false){
        
        let message = NWProtocolFramer.Message(videoMessageType: type)
        let context = NWConnection.ContentContext(identifier: id, metadata: [message])
        connection.send(content: data, contentContext: context, isComplete: true, completion: idempotent ? .idempotent : .contentProcessed({ error in
            if let error = error{
                self.log(error.debugDescription, color: .systemRed)
            }
        }))
        awaitNextMessage()
    }
    func awaitNextMessage(){
        connection.receiveMessage(completion: self.handleMessageReceived)
    }
    
    func handleMessageReceived(data: Data?, context: NWConnection.ContentContext?, isComplete: Bool, error: NWError?){
        guard let message = context?.protocolMetadata(definition: VideoProtocol.definition) as? NWProtocolFramer.Message, let data = data else {
            log("Bad data received \(String(describing: data))", color: .red)
            return
        }
        
        switch message.videoMessageType{
        case .cameraAvailable:
            DispatchQueue.main.async{
                self.name = (String(data: data, encoding: .utf8) ?? "")
                self.log("\(self.name) is available", color: .systemGreen)
                self.delegate?.shootCameraWasIdentified(camera: self)
            }
            
        case .hevcParameterSet:
            if let parameterSet = try? JSONDecoder().decode(H265ParameterSet.self, from: data){
                self.log(message: "HEVC parameter set received from Shoot (\(parameterSet.parameters), decoder exists? \(self.decoder != nil))", color: .systemOrange)
                // this can happen in response to a video request but also if the resolution or frame rate changes
                self.createDecoder()
                
                self.decoder?.parameterSet = parameterSet.parameters
            }else{
                self.log(message: "Error parsing HEVC parameter set from iPad \(data)", color: .systemRed)
            }
        case .videoFrame:
            self.decode(frame: data)
            
        case .control:
            DispatchQueue.main.async {
                self.handleControl(data: data)
            }
        default:
            log("Ignored message type \(message.videoMessageType)", color: .systemOrange)
        }
        awaitNextMessage()
    }
    
    public func startVideoStream(){
        sendFramedMessage(data: "start".data(using: .utf8), id: "video stream for \(id)", type: .requestVideoStream)
        isRunning = true
    }
    
    public func stopVideoStream(){
        sendFramedMessage(data: "stop".data(using: .utf8), id: "video stream should end", type: .cancelVideoStream)
        isRunning = false
    }
    
    var decoder: H265Decoder?
    func createDecoder(){
        log("Creating Decoder", color: .green)
    
        if decoder != nil {
            log("Removing old decoder", color: .orange)
            decoder = nil
        }
        
        decoder = H265Decoder()
        decoder?.setConfig(width: 1920, height: 1080)
        decoder?.delegate = self
        
    }
    func decode(frame: Data){
        if decoder == nil {
            log("Suspicious lazy decoder creation", color: .red)
            createDecoder()
        }
        decoder?.decode(frame)
    }
    

    let jsonDecoder = JSONDecoder()
    let jsonEncoder = JSONEncoder()
    func handleControl(data: Data){
        guard let message = try? jsonDecoder.decode(BasicControlMessage<ShootControlMessage>.self, from: data)
        else { return }
        
        // CALLED ON MAIN THREAD
        
        switch message.command{
        case .remoteDeviceIdentifier:
            if let id = message.stringArguments?.first{
                self.remoteDeviceIdentifier = id
            }
        case .availableSources:
            if let sources =  message.stringArguments?.compactMap({ try? jsonDecoder.decode(VideoSourceProxy.self, from: $0.data(using: .utf8)!)}){
                self.sources = sources
            }
        case .availableControls:
            if let controls = message.stringArguments?.compactMap({ try? jsonDecoder.decode(VideoSourceControlProxy.self, from: $0.data(using: .utf8)!)}){
                self.controls = controls
            }
        case .settings:
            if let settings = decode(ShootSettings.self, from: message){
                self.settings = settings
            }
        case .currentValues:
            if let values = decode(DeviceValues.self, from: message){
                objectWillChange.send()
                for dict in values.values{
                    var controlId: String?
                    var controlValueChange: VideoSourceControlChange<Float>?
                    for (key, value) in dict {
                        if key == "message-key"{
                            controlId = value
                        }
                        if key == "control-value-changed", let data = value.data(using: .utf8), let change = try? jsonDecoder.decode(VideoSourceControlChange<Float>.self, from: data){
                            controlValueChange = change
                        }
    
                    }
                
                    if let controlId = controlId, let change = controlValueChange{
                        DispatchQueue.main.async {
                            self.values[controlId] = change.value.value.toFloat
                        }
                    }
                }
                for dict in values.auto{
                    var controlId: String?
                    var controlValueToggle: VideoSourceControlToggle?
                    for (key, value) in dict {
                        if key == "message-key"{
                            controlId = value
                        }
                        if key == "control-value-toggled", let data = value.data(using: .utf8), let change = try? jsonDecoder.decode(VideoSourceControlToggle.self, from: data){
                            controlValueToggle = change
                        }
                    }
                
                    if let controlId = controlId, let toggle = controlValueToggle{
                        DispatchQueue.main.async {
                            self.autoValues[controlId] = toggle.value
                        }
                    }
                }
            }
        
        case .selectedSource:
            if let source = decode(VideoSourceProxy.self, from: message){
                DispatchQueue.main.async {
                    self.selectedSource = source
                }
            }
        default:
            break
        }
        
        
    }
    
    func decode<T:Codable>(_ type: T.Type, from message: BasicControlMessage<ShootControlMessage>)->T?{
        if let data = message.stringArguments?.first?.data(using: .utf8){
            return try? jsonDecoder.decode(type, from: data)
        }
        return nil
    }
    
    public func send(change: VideoSourceControlChange<Float>.JSON){
        send(command: .controlChange, values: [change])
    }
    public func send(settings: ShootSettings){
        send(command: .settings, values: [settings])
        
    }
    public func send(toggle: VideoSourceControlToggle){
        send(command: .controlToggle, values: [toggle])
    }
    public func select(sourceNamed name: String){
        if let source = sources.first(where: {$0.title == name}){
            select(sourceId: source.id)
        }
    }
    public func select(sourceId: String){
        let command = ShootControlMessage.selectedSource
        let message = BasicControlMessage(command: command, stringArguments: [sourceId])
        if let data = try? jsonEncoder.encode(message){
            sendFramedMessage(data: data, id: UUID().uuidString, type: .control)
        }
    }
    public func sendSelectedSource(){
        if let id = selectedSource?.id {
            select(sourceId: id)
        }
    }
    private func send(command: ShootControlMessage, values: [Codable]){
        let stringValues = values.compactMap({ try? jsonEncoder.encode($0)}).compactMap({String(data: $0, encoding: .utf8)})
        let message = BasicControlMessage(command: command, stringArguments: stringValues)
        if let data = try? jsonEncoder.encode(message){
            sendFramedMessage(data: data, id: UUID().uuidString, type: .control)
        }
    }
    func send<T>(basicMessage: BasicControlMessage<T>){
        guard let data = try? JSONEncoder().encode(basicMessage) else { return }
        let message = NWProtocolFramer.Message(videoMessageType: .control)
        let context = NWConnection.ContentContext(identifier: "control", metadata: [message])
        
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                self?.log(message: "Error sending control message " + error.debugDescription, color: .red)
            }
        }))
            
        awaitNextMessage()
    }
}

extension ShootCamera: Equatable{
    public static func == (lhs: ShootCamera, rhs: ShootCamera) -> Bool {
        lhs.id == rhs.id
    }
}

extension ShootCamera: Hashable{
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}


extension ShootCamera: H265DecoderDelegate{
    
    var shouldCreateSampleBuffers: Bool { true }
    
    func videoDecoderDidDecodePixelBuffer(_ decoder: H265Decoder, pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, presentationDuration: CMTime) {
        self.latestPixelBuffer = pixelBuffer
    }
    
    func videoDecoderDidDecodeSampleBuffer(_ decoder: H265Decoder, sampleBuffer: CMSampleBuffer) {
        self.latestSampleBuffer = sampleBuffer
    }
    
    func videoDecoder(_ decoder: H265Decoder, failedWith error: OSStatus) {
        // already logged by the decoder
    }
}

extension ShootCamera: ConnectionLogger{
    public func log(_ text: String, color: NSColor) {
        logger.log(text, color: color)
    }
    
    public func log(message: String, color: NSColor) {
        logger.log(message, color: color)
    }
}
