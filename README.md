# ShootKit
By Michael Forrest
[Good To Hear Ltd](https://goodtohear.co.uk)

ShootKit lets you add [Shoot](https://squares.tv/shoot) and [Video Pencil](https://squares.tv/videopencil) support to your MacOS applications.

## Features 
* Integrate Video Pencil 
* Video feed from Shoot Pro Camera Source app
* Enumerate and switch Shoot's camera sources 
* Shoot control panel using SwiftUI (use NSHostingController to add to your non-SwiftUI or Objective-C project)

## Installation

```
pod 'ShootKit', git: 'https://github.com/goodtohear/ShootKit.git', branch: 'main'
```

To get the latest version, run `pod update ShootKit`.

Add to Bonjour Services (Info.plist)
```
 _videopencil_ios._tcp
 _shoot_receiver._tcp
 ```

## VideoPencilClient
The [Video Pencil](https://videopencil.com?ct=ShootKit) client lets you:
1. Send a video feed to the iPad
2. Receive a transparent video overlay

### Objective-C
```objectivec
@import ShootKit;

// Create VideoPencilClient
self.videoPencilClient =  [
    [VideoPencilClient alloc] initWithName: @"My Video App"
                                      size: CGSizeMake(1920, 1080)
                                  delegate: self
                                     queue: self.callbackQueue
                                 ciContext: nil
    ];

// Send video frame to iPad:
[self.videoPencilClient sendFrame: ciImage presentationTimeStamp: time presentationDuration: duration];

// Receive drawing frames as `VideoPencilClientDelegate`
- (void)videoPencilDidReceiveFrom:(VideoPencilClient * _Nonnull)from frame:(CIImage _Nonnull)frame presentationTimeStamp:(CMTime) presentationDuration:(CMTime)presentationDuration{
    // use `frame` in your CoreImage pipeline
}

```

Drawing frames reach the delegate evenly paced, each at its display time on the Mac's host clock (passed as `presentationTimeStamp`), a few hundredths of a second after it was drawn on the iPad. To get each frame as soon as it's decoded and pace them yourself, set `pacesReceivedFrames` to `false`.


### Swift
```swift
// Create VideoPencilClient
let client = VideoPencilClient(name: "My Video App", delegate: self, queue: callbackQueue, ciContext: nil)

// Send video frame to iPad
client.send(frame: ciImage, presentationTimeStamp: time, presentationDuration: duration)

// Receive drawing frames as `VideoPencilClientDelegate`
func videoPencilDidReceive(from: VideoPencilClient, frame: CIImage, presentationTimeStamp: CMTime, presentationDuration: CMTime) {
      // use `frame` in your CoreImage pipeline 
}
```

## Get started
Check the sample projects 
* [ShootKit Swift Sample](ShootKit/Sample%20Projects/Swift%20Sample)
* [ShootKit Objective-C Sample](ShootKit/Sample%20Projects/Objective-C%20Sample)

*Shoot samples require >=3.8.1 to work*

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
  - `videoPencilDidReceive(from: VideoPencilClient, sampleBuffer: CMSampleBuffer)` -> receive transparent video feed in your delegate

## Get help
Find me @michaelforrest on [Discord](https://discord.gg/ZJBHyb5tTP)!
