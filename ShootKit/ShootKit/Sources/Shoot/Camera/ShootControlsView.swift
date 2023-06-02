//
//  ShootControlsView.swift
//  Video Pencil Camera
//
//  Created by Michael Forrest on 23/03/2023.
//

import SwiftUI

extension ShootSettings.FaceFollow{
    mutating func set(scale: Float){
        self.scale = min(max(minScale,scale),maxScale)
    }
    mutating func set(rate: Float){
        self.rate = min(max(minRate, rate),maxRate)
    }
}

public struct ShootControlsView: View {
    @ObservedObject public var camera: ShootCamera

    public init(camera: ShootCamera) {
        self.camera = camera
    }
    
    var faceFollowToggleBinding: Binding<Bool>{
        .init(get: {
            camera.settings?.faceFollow?.enabled == true
        }, set: { value in
            camera.settings?.faceFollow?.enabled = value
            camera.send(settings: camera.settings!)
        })
    }
    var faceFollowRateBinding: Binding<Float>{
        .init(get: {camera.settings?.faceFollow?.rate ?? 0.1}, set: {
            camera.settings?.faceFollow?.set(rate: $0)
            camera.send(settings: camera.settings!)
        })
    }
    var faceFollowScaleBinding: Binding<Float>{
        .init(get: {camera.settings?.faceFollow?.scale ?? 0.2}, set: {
            camera.settings?.faceFollow?.set(scale: $0)
            camera.send(settings: camera.settings!)
        })
    }
    
    var sourceBinding: Binding<String>{
        .init {
            camera.selectedSource?.id ?? "unknown-from-vpc-controls"
        } set: { sourceId in
            camera.selectedSource = camera.sources.first(where: {$0.id == sourceId})
            camera.sendSelectedSource()
        }

    }
    
    public var body: some View {
        VStack(alignment: .leading){
            if camera.controls.count == 0{
                ProgressView().progressViewStyle(.linear)
            }
            ForEach(camera.controls, id: \.id){control in
                ShootControlView(control: control, camera: camera)
            }
            if let faceFollow = camera.settings?.faceFollow{
                Divider()
                Toggle(isOn: faceFollowToggleBinding) {
                    HStack{
                        Text("Face Follow")
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
                
                HStack{
                    Slider(value: faceFollowRateBinding, in: faceFollow.rateRange){
                        Text("Rate")
                    }
                    TextField("", value: faceFollowRateBinding, formatter: .floatFormatter).frame(width: 32)
                }
                HStack{
                    Slider(value: faceFollowScaleBinding, in: faceFollow.scaleRange){
                        Text("Scale")
                    }
                    TextField("", value: faceFollowScaleBinding, formatter: .floatFormatter).frame(width: 32)
                }
            }
        }
    }
}

public struct ShootControlView: View{
    var control: VideoSourceControlProxy
    @ObservedObject public var camera: ShootCamera
    @State var discreteIndex: Int = 0
    
    var binding: Binding<Float>{
        .init {
            camera.values[control.id] ?? 0
        } set: { value in
            camera.values[control.id] = value
            camera.autoValues[control.id] = false
            camera.send(change: VideoSourceControlChange.JSON(control: CameraControl(rawValue: control.id)!, value: ControlValue<Float>(value, origin: .videoPencilCamera)))
        }

    }
    
    var discreteBinding: Binding<Float>{
        .init {
            if let value = camera.values[control.id], let index = control.scale.minorTickValues.firstIndex(of: value){
                return Float(index)
            }else{
                return 0
            }
        } set: { index in
            let value = control.scale.minorTickValues[Int(index)]
            camera.values[control.id] = value
            camera.autoValues[control.id] = false
            camera.send(change: VideoSourceControlChange<Float>.JSON(control: CameraControl(rawValue: control.id)!, value: ControlValue<Float>(value, origin: .videoPencilCamera)))
        }
    }
    
    public var body: some View{
        HStack {
            Text(control.title)
            Spacer()
            if control.scale.isDiscrete{
                Slider(value: discreteBinding, in: 0...Float(control.scale.minorTickValues.count-1), step: 1){ _ in
                    
                }
            }else{
                Slider(value: binding, in: control.scale.majorTickValues.first!...control.scale.majorTickValues.last!) { _ in
                    
                }

            }
            if camera.autoValues[control.id] == false{
                Button {
                    camera.autoValues[control.id] = true
                    camera.send(toggle: .init(id: control.id, value: true))
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.caption)
    }
}

//struct ShootControlsView_Previews: PreviewProvider {
//    static var previews: some View {
//        ShootControlsView()
//    }
//}
