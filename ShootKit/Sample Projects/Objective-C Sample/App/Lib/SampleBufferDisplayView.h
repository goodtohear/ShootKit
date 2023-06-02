//
//  SampleBufferDisplayview.h
//  Objective-C Sample
//
//  Created by Michael Forrest on 02/06/2023.
//

#import <Cocoa/Cocoa.h>
@import AVKit;

NS_ASSUME_NONNULL_BEGIN

@interface SampleBufferDisplayView : NSView
-(AVSampleBufferDisplayLayer*)sampleBufferLayer;
@end

NS_ASSUME_NONNULL_END
