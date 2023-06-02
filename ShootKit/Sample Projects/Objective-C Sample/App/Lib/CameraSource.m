//
//  CameraSource.m
//  Objective-C Sample
//
//  Created by Michael Forrest on 02/06/2023.
//

#import "CameraSource.h"
@import AVKit;

@interface CameraSource(){
    AVCaptureSession * session;
    AVCaptureVideoDataOutput* output;
    dispatch_queue_t queue;
}
@property (weak,nonatomic) id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate;
@end


@implementation CameraSource
- (instancetype)initWithCaptureDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate{
    self = [super init];
    if (self) {
        self.delegate = delegate;
        [self build];
    }
    return self;
}

-(void)build{
    self.availableCameras = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeExternalUnknown] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified].devices;
    
    session = [[AVCaptureSession alloc] init];
    output = [[AVCaptureVideoDataOutput alloc] init];
    queue = dispatch_queue_create("camera", DISPATCH_QUEUE_SERIAL);
    
    [session beginConfiguration];
    output.videoSettings = [[NSDictionary alloc] initWithObjectsAndKeys:@(kCVPixelFormatType_32BGRA),(NSString*)kCVPixelBufferPixelFormatTypeKey , nil];
    output.alwaysDiscardsLateVideoFrames = true;
    [output setSampleBufferDelegate:self.delegate queue:queue];
    [session addOutput:output];
    [session commitConfiguration];
    
    [self selectCamera: self.availableCameras.firstObject];
}
-(void)selectCamera:(AVCaptureDevice *)camera{
    self.selectedCamera = camera;
    
    NSError*error;
    AVCaptureDeviceInput * input = [[AVCaptureDeviceInput alloc] initWithDevice:camera error:&error];
    
    [session stopRunning];
    [session beginConfiguration];
    [session.inputs enumerateObjectsUsingBlock:^(__kindof AVCaptureInput * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [session removeInput:obj];
    }];
    [session addInput:input];
    [session commitConfiguration];
    [session startRunning];
}

@end
