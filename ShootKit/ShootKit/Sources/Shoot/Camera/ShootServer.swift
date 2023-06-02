//
//  ShootServer.swift
//  TelestratorApp
//
//  Created by Michael Forrest on 29/01/2023.
//

import Foundation
import Network
import AppKit

public protocol ShootServerDelegate{
    func shootServerDidDiscover(camera: ShootCamera)
    func shootServerWasDisconnected(from camera: ShootCamera)
}

public class ShootServer: ObservableObject{
    public let logger = BaseConnectionLogger()
    private var bonjourListener: NWListener?
    private let queue = DispatchQueue(label: "Shoot Connection Queue", qos: .userInitiated)
    
    public var cameras = [ShootCamera]()
    
    var name: String
    public var delegate: ShootServerDelegate?
   
    public init(name: String, delegate: ShootServerDelegate?){
        self.name = name
        self.delegate = delegate
        startBonjourServer()
    }
    
    func startBonjourServer(){
        if bonjourListener == nil{
            bonjourListener = try? NWListener(using: ShootKit.applicationServiceParameters())
            bonjourListener?.service = NWListener.Service(type:  .shootReceiver)
        }
        guard let bonjourListener = bonjourListener else { return }
        bonjourListener.stateUpdateHandler = handleBonjourStateUpdate
        bonjourListener.newConnectionHandler = handleNewBonjourConnection
        bonjourListener.start(queue: queue)
    }
    func handleBonjourStateUpdate(state: NWListener.State){
        log(message: "Shoot Server state: \(state) \(String(describing: bonjourListener!.service!))", color: .systemOrange)
    }
    func handleNewBonjourConnection(newConnection: NWConnection){
        log(message: "New Shoot connection \(newConnection.endpoint)", color: .green)
        let camera = ShootCamera(connection: newConnection, delegate: self)
        // add Shoot to camera options
        DispatchQueue.main.async {
            self.cameras.append(camera)
        }
    }
}
extension ShootServer: ShootCameraDelegate{
    public func shootCameraWasIdentified(camera: ShootCamera) {
        delegate?.shootServerDidDiscover(camera: camera)
    }
    public func shootCameraWasDisconnected(camera: ShootCamera) {
        cameras.removeAll(where: {$0.name == camera.name })
        delegate?.shootServerWasDisconnected(from: camera)
    }
}

extension ShootServer: ConnectionLogger{
    public func log(_ text: String, color: NSColor) {
        logger.log(text, color: color)
    }
    
    public func log(message: String, color: NSColor) {
        logger.log(message, color: color)
    }

}

