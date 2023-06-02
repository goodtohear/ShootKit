# ShootKit
By Michael Forrest
[Good To Hear Ltd](https://goodtohear.co.uk)

ShootKit lets you add [Shoot](https://squares.tv/shoot) and [Video Pencil](https://squares.tv/videopencil) support to your MacOS applications.

## Features 
* Video feed from Shoot - just implement a delegate to handle the `CMSampleBuffer` stream
* Enumerate and switch Shoot's camera sources 
* Shoot control panel using SwiftUI (use NSHostingController to add to your non-SwiftUI or Objective-C project)
* Bi-directional Video Pencil feeds - send a reference layer to Video Pencil and receive a transparent overlay back

## Try it out
Check the sample projects [Swift](ShootKit/Sample%20Projects/Swift%20Sample) [Objective-C](ShootKit/Sample%20Projects/Objective-C%20Sample)

## Add to your project
* Drag the project 

```
init(){
  let listener = ShootListener.shared
  listener.delegate = self
}

/// implement
func newShootCameraFound(camera: ShootCamera){
  self.cameras.append(camera)
  camera.delegate = self

  // access camera features
  camera.controls
  camera.values


  camera.requestVideoStream()
}

func shootCameraDidReceive(sampleBuffer: CMSampleBuffer){
  // present the sample buffer or extract the CVPixelBufffer with CMSampleBufferGetImageBuffer
}
```
