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

Clone this project and drag it into your Xcode project, then add ShootKit as a dependency to your project.

Important classes:

`ShootServer` - discover running instances of Shoot

`ShootControlsView` - manual controls for connected Shoot camera

`VideoPencilClient` - connect to Video Pencil, send and receive video
