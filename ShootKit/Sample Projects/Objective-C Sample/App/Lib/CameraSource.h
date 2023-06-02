//
//  CameraSource.h
//  Objective-C Sample
//
//  Created by Michael Forrest on 02/06/2023.
//

#import <Foundation/Foundation.h>
@import AVKit;

NS_ASSUME_NONNULL_BEGIN

@interface CameraSource : NSObject
-(instancetype)initWithCaptureDelegate: (id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate;

@property(strong,nonatomic) NSMutableArray<AVCaptureDevice*>*availableCameras;
@property(strong, nonatomic) AVCaptureDevice* selectedCamera;

-(void)selectCamera: (AVCaptureDevice* )camera;

@end

NS_ASSUME_NONNULL_END
