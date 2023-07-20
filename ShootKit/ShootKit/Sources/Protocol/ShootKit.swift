//
//  ShootKitProtocol.swift
//  ShootKit
//
//  Created by Michael Forrest on 02/06/2023.
//

import Foundation
import Network

struct ShootKit{
    static func applicationServiceParameters() -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2
        
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        
        parameters.multipathServiceType = .disabled
        parameters.serviceClass = .interactiveVideo
        parameters.allowLocalEndpointReuse = false // true
        parameters.allowFastOpen = true
        
        let videoOptions = NWProtocolFramer.Options(definition: VideoProtocol.definition)
        parameters.defaultProtocolStack.applicationProtocols.insert(videoOptions, at: 0)
        
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        return parameters
    }
    
    static func nwBrowser(for type: BonjourServiceName)->NWBrowser{
        NWBrowser(for: .bonjour(type: type.rawValue, domain: nil), using: applicationServiceParameters())
    }
    
    enum BonjourServiceName: String{
        case shootReceiver = "_shoot_receiver._tcp"
        case videoPencilApp = "_videopencil_ios._tcp"
    }

}

extension NWListener.Service{
    init(type: ShootKit.BonjourServiceName){
        self.init(type: type.rawValue)
    }
}
