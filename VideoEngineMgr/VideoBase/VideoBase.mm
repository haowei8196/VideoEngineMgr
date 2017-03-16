//
//  VideoTask.m
//  aneVideo
//
//  Created by mac on 13-4-1.
//  Copyright (c) 2013年 Ib. All rights reserved.
//

#import "VideoBase.h"
#import "VideoRenderFrame.h"


#ifdef __cplusplus
extern "C" {
#endif
#include "libavformat/avformat.h"
#ifdef __cplusplus
}  // extern "C"
#endif

static NSMutableArray*         _freeChannels = nil;
@interface VideoBase ()
{
    NSTimeInterval   _lastSendDate;
    int32_t   _curDatasize;
}
@end

@implementation VideoBase
+ (void)Initialize
{
    _freeChannels = [[NSMutableArray alloc] initWithCapacity:__MAX_REMOTE_VIDEOS];
    for(int i = 0; i< __MAX_REMOTE_VIDEOS; ++i)
    {
        [_freeChannels addObject:@(i)];
    }
}
+ (NSNumber*)CreateChannel
{
    if([_freeChannels count] == 0)
        return nil;
    
    NSNumber *tmp = [_freeChannels objectAtIndex:0];
    [_freeChannels removeObjectAtIndex:0];
    return tmp;
}
+ (void)ReleaseChannel:(NSNumber*)channelid
{
    int i = [channelid intValue];
    if(i<0 || i >= __MAX_REMOTE_VIDEOS)
        return;
    
    [_freeChannels addObject:channelid];
}
+ (void)Destroy
{
    _freeChannels = nil;
}

-(id)init
{
    self = [super init];
    if(self)
    {
        _curDatasize = 0;
    }

    return self;
}

- (void)NewPack:(int)size
{

}

- (void)lowBandWidth
{
    
}

- (int)StartRender:(UIView*)parentView Scaling:(int)scaling
{
    return 0;
}

- (void)StopRender
{
    dispatch_sync(dispatch_get_main_queue(), ^{
        
        [_renderFrame removeFromSuperview];
        _renderFrame = nil;
    });
}

- (void)Pause
{
    AVLogInfo(@"Pause render %@", _channelid); 
}

- (void)Resume
{
    
}

- (NSMutableData*)dataWithLines:(uint8_t*)data W:(int)w H:(int)h LineSize:(int)linesize
{
    NSMutableData *theData = [NSMutableData dataWithCapacity:w * h];
    for (int i = 0; i < h; ++i)
    {
        [theData appendBytes:(data + i * linesize) length:w];
    }
    
    return theData;
}

- (void)setScaling:(int)scaling
{
    if (self.scalingType == scaling)
    {
        return;
    }
    
    self.scalingType = scaling;
    if (_renderFrame)
    {
        [_renderFrame setScalingType:self.scalingType];
    }
}

@end
