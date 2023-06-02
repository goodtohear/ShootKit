//
//  SampleBufferDisplayview.m
//  Objective-C Sample
//
//  Created by Michael Forrest on 02/06/2023.
//

#import "SampleBufferDisplayView.h"
@import AVKit;

@implementation SampleBufferDisplayView
- (CALayer *)makeBackingLayer{
    return [AVSampleBufferDisplayLayer layer];
}
- (instancetype)initWithFrame:(NSRect)frameRect{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self build];
    }
    return self;
}
- (AVSampleBufferDisplayLayer *)sampleBufferLayer{
    return (AVSampleBufferDisplayLayer*) self.layer;
}
-(void)awakeFromNib{
    [super awakeFromNib];
    [self build];
}

-(void)build{
    self.wantsLayer = true;
}
@end
