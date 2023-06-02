//
//  ShootDemoView.swift
//  ShootKit
//
//  Created by Michael Forrest on 02/06/2023.
//

import SwiftUI
import ShootKit

struct ShootDemoView: View {
    @StateObject var state = ShootState()
    var body: some View {
        VStack(spacing: 16) {
            if state.cameras.count == 0{
                ProgressView {
                    Text("Launch Shoot on a device on the same network as this Mac")
                }
                Button {
                    NSWorkspace.shared.open(URL(string:"https://squares.tv/shoot?ct=shootkit")!)
                } label:{
                    Text("Get Shoot")
                }
            }
            ForEach(Array(state.cameras)){ camera in
                ShootCameraRow(camera: camera, selectedCameraName: camera.selectedSource?.title)
            }
        }
        .padding()
    }
}

extension ShootCamera: SampleBufferSource{}

struct ShootCameraRow: View{
    @ObservedObject var camera: ShootCamera
    @State var selectedCameraName: String?
    var body: some View{
        VStack {
            HStack{
                if camera.isRunning{
                    SampleBufferPlayer(sampleBufferSource: camera)
                }
                ShootControlsView(camera: camera)
            }
            HStack{
                Text(camera.name)
                if camera.isRunning{
                    Button("Stop Video"){
                        camera.stopVideoStream()
                    }
                }else{
                    Button("Start Video"){
                        camera.startVideoStream()
                    }
                }
            }
            Picker("Camera", selection: .init(get: {
                selectedCameraName
            }, set: { value in
                selectedCameraName = value
                if let value = value{
                    camera.select(sourceNamed: value)
                }
            })){
                ForEach(camera.sources){ source in
                    Text(source.title).tag(Optional<String>(source.title))
                }
            }
        }
    }
}

struct ShootDemoView_Previews: PreviewProvider {
    static var previews: some View {
        ShootDemoView()
    }
}
