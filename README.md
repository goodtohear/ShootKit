# ShootKit
By Michael Forrest
[Good To Hear Ltd](https://goodtohear.co.uk)

ShootKit lets you add [Shoot](https://squares.tv/shoot) and [Video Pencil](https://squares.tv/videopencil) support to your MacOS applications.

## Features 
* Video feed from Shoot - just implement a delegate to handle the `CMSampleBuffer` stream
* Enumerate and switch Shoot's camera sources 
* Shoot control panel using SwiftUI (use NSHostingController to add to your non-SwiftUI or Objective-C project)
* Bi-directional Video Pencil feeds - send a reference layer to Video Pencil and receive a transparent overlay back

## Get started
Check the sample projects 
* [ShootKit Swift Sample](ShootKit/Sample%20Projects/Swift%20Sample)
* [ShootKit Objective-C Sample](ShootKit/Sample%20Projects/Objective-C%20Sample)
Shoot samples require >=3.8.1 to work. 

Clone this project and drag it into your Xcode project, then add ShootKit as a dependency to your project.

You'll need to enable the following under **Bonjour services** in your Info.plist:

For Shoot: `_shoot_receiver._tcp`

For Video Pencil: `_videopencil_ios._tcp`


Important classes:

`ShootServer` - discover running instances of Shoot
 - delegate callbacks when devices discovered
 - receive callbacks with CMSampleBuffers on the server delegate or on individual camera delegates
 
 `ShootCamera`
 - Call `startVideoStream` to start receiving buffers

`ShootControlsView` - manual controls for connected Shoot camera
 - Instantiate in SwiftUI or using `ShootControlsViewFactory.makeShootControls(for camera: minWidth:)->NSViewController`

`VideoPencilClient` - connect to Video Pencil, send and receive video
  - `send(sampleBuffer:CMSampleBuffer)` -> Send feed to Video Pencil
  - `videoPencilDidReceive(from: VideoPencilClient, sampleBuffer: CMSampleBuffer)` -> recieve transparent video feed in your delegate

## Get help
Find me @michaelforrest on [Discord](https://discord.gg/ZJBHyb5tTP)!
