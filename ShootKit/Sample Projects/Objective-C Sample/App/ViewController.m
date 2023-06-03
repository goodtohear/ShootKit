//
//  ViewController.m
//  Objective-C Sample
//
//  Created by Michael Forrest on 02/06/2023.
//

#import "ViewController.h"
#import "Lib/SampleBufferDisplayView.h"
#import "Lib/CameraSource.h"

@import ShootKit;
@import AVKit;

@interface ViewController()<ShootServerDelegate, VideoPencilClientDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>{
    NSMutableSet<ShootCamera*>*shootCameras;
    CMSampleBufferRef latestVideoPencilBuffer;
    CMSampleBufferRef latestCameraBuffer;
    NSViewController * shootControlsViewController;
}

@property(strong, nonatomic) ShootServer * shootServer;

@property(strong, nonatomic) VideoPencilClient * videoPencilClient;

@property(strong, nonatomic) CameraSource * cameraSource;

@property (weak) IBOutlet SampleBufferDisplayView *shootCameraView;
@property (weak) IBOutlet NSTextField *shootInfoLabel;
@property (weak) IBOutlet NSStackView *shootStackView;
@property (weak) IBOutlet NSView *shootControlsContainer;

@property (weak) IBOutlet SampleBufferDisplayView *cameraPreview;
@property (weak) IBOutlet SampleBufferDisplayView *videoPencilLayerView;
@property (weak) IBOutlet NSTextField *videoPencilLabel;
@property (weak) IBOutlet NSStackView *videoPencilStackView;
@end


@implementation ViewController{
    
}

- (void)viewDidLoad {
    [super viewDidLoad];
    shootCameras = [[NSMutableSet alloc] init];
    latestVideoPencilBuffer = nil;
    self.shootServer = [[ShootServer alloc] initWithName: @"Obj-C Demo" delegate: self];
    self.videoPencilClient = [[VideoPencilClient alloc] initWithName: @"Obj-C Demo" delegate: self];
    
    [self startMacCamera];
}



#pragma mark - ShootServerDelegate
-(BOOL)shootCameraShouldCreateSampleBuffers{
    return true; // otherwise you just get CVPixelBuffers
}
- (void)shootServerDidDiscoverWithCamera:(ShootCamera *)camera{
    [shootCameras addObject:camera];
    [camera startVideoStream];
    
    self.shootInfoLabel.stringValue = camera.name;
    
    
    // Supply ShootCamera buffers to self.shootCameraView
    AVSampleBufferDisplayLayer * layer = self.shootCameraView.sampleBufferLayer;
    [layer requestMediaDataWhenReadyOnQueue:dispatch_get_main_queue() usingBlock:^{
        if(layer.isReadyForMoreMediaData){
            [layer enqueueSampleBuffer: camera.latestSampleBuffer];
        }
    }];
    
    // Add the camera controls
    if(shootControlsViewController != nil) return;
    
    shootControlsViewController = [ShootControlsViewFactory makeShootControlsFor:camera minWidth: 300];
    
    NSWindow *floatingWindow = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 600, 400)
                                                           styleMask: NSWindowStyleMaskResizable  | NSWindowStyleMaskTitled | NSWindowStyleMaskHUDWindow
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
    [floatingWindow setTitle: camera.name];
    [floatingWindow setLevel: NSNormalWindowLevel];
    [floatingWindow setContentViewController: shootControlsViewController];
    [floatingWindow makeKeyAndOrderFront:nil];
    
}

- (void)shootServerWasDisconnectedFrom:(ShootCamera * _Nonnull)camera {
    [shootCameras removeObject: camera];
}

#pragma mark - Mac Camera
-(void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    latestCameraBuffer = (CMSampleBufferRef) CFRetain(sampleBuffer);
    [self.videoPencilClient sendWithSampleBuffer: latestCameraBuffer];
}

#pragma mark - VideoPencilClientDelegate
-(BOOL)videoPencilClientShouldCreateSampleBuffers{
    return true;
}
- (void)videoPencilDidConnect:(VideoPencilClient * _Nonnull)client {
    self.videoPencilLabel.stringValue = @"Connected to Video Pencil";
    
    // Supply Video Pencil transparent buffers to self.videoPencilLayerView which is on top of the camera preview
    AVSampleBufferDisplayLayer* layer = self.videoPencilLayerView.sampleBufferLayer;
    [layer requestMediaDataWhenReadyOnQueue:dispatch_get_main_queue() usingBlock:^{
        if(layer.isReadyForMoreMediaData && self->latestVideoPencilBuffer != nil){
            [layer enqueueSampleBuffer: self->latestVideoPencilBuffer];
        }
    }];
}

- (void)videoPencilDidDisconnect:(VideoPencilClient * _Nonnull)client {
    self.videoPencilLabel.stringValue = @"Disconnected";
}


- (void)videoPencilDidReceiveFrom:(VideoPencilClient * _Nonnull)from sampleBuffer:(CMSampleBufferRef _Nonnull)sampleBuffer {
    latestVideoPencilBuffer = (CMSampleBufferRef) CFRetain(sampleBuffer);
}

#pragma mark - Demo-specific

-(void)startMacCamera{
    
    self.cameraSource = [[CameraSource alloc] initWithCaptureDelegate:self];
    AVSampleBufferDisplayLayer * layer = self.cameraPreview.sampleBufferLayer;
    [layer requestMediaDataWhenReadyOnQueue:dispatch_get_main_queue() usingBlock:^{
        if(layer.isReadyForMoreMediaData && self->latestCameraBuffer != nil){
            [layer enqueueSampleBuffer: self->latestCameraBuffer];
        }
    }];
    
}


#pragma mark - All the other protocol callbacks for reference

- (void)videoPencilDidReceiveFrom:(VideoPencilClient * _Nonnull)from pixelBuffer:(CVPixelBufferRef _Nonnull)pixelBuffer {
    
}
// bit awkward that I'm pushing the individual camera callbacks to the server delegate
// this can be refined in time.
- (void)shootCameraWasDisconnectedWithCamera:(ShootCamera * _Nonnull)camera {
    
}

- (void)shootCameraWasIdentifiedWithCamera:(ShootCamera * _Nonnull)camera {
    
}

- (void)shootCameraWithCamera:(ShootCamera * _Nonnull)camera didReceivePixelBuffer:(CVPixelBufferRef _Nonnull)pixelBuffer presentationTimeStamp:(CMTime)presentationTimeStamp presentationDuration:(CMTime)presentationDuration {
    
}

- (void)shootCameraWithCamera:(ShootCamera * _Nonnull)camera didReceiveSampleBuffer:(CMSampleBufferRef _Nonnull)sampleBuffer {
    
}
@end
