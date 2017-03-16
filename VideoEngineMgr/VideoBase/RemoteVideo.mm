//
//  anetest.m
//  anetest
//
//  Created by mac on 13-2-26.
//  Copyright (c) 2013年 Ib. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#import "RemoteVideo.h"
#import "H264Decoder.h"
#import "VideoEngineMgr.h"
#import "VideoRenderFrame.h"


@interface RemoteVideo ()<H264DecoderDelegate>

@property (nonatomic, strong) H264Decoder *decoder;
@property (nonatomic, weak) id<VideoDelegate> delegate;
@property (nonatomic, strong) UIView *displayView;
@end

@implementation RemoteVideo

#pragma mark - Outlets
- (id)initWithDelegate:(id)delegate Channel:(NSNumber*)channel
{
    self = [super init];
    if(self != nil)
    {
        _delegate = delegate;
        self.channelid = channel;
        _decoder = [H264Decoder create];
        [_decoder registerDelegate:self];

        if ([NSStringFromClass(_decoder.class) isEqualToString:@"H264DecoderImpl"]) {//
            [self.delegate onWarning:Warning_HardWareDecode_NotSupported];
        }

    }
    return self;
}

- (void)dealloc
{
    _delegate = nil;
    if (_decoder) {
        [H264Decoder destroy:_decoder];
        _decoder = nil;
    }
}

- (void)pause
{
    [self StopRender];
}

- (void)resume:(UIView*)window
{
    //[self StartRender:window];
    if (window && _displayView != window) {
        _displayView = window;
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (_renderFrame) {
                [_renderFrame removeFromSuperview];
                _renderFrame = nil;
            }
        });
        [self StartRender:window Scaling:self.scalingType];
    }
}
- (int)StartRender:(UIView*)parentView Scaling:(int)scaling
{
    dispatch_async(dispatch_get_main_queue(), ^{
        
        if(parentView == nil || _renderFrame != nil)
            return;
        VideoRenderFrame *renderFrame = [[VideoRenderFrame alloc] initWithParent:parentView Preview:nil];
        _renderFrame = renderFrame;
        [_renderFrame setScalingType:scaling];
    });
    return 0;
}
- (void)lowBandWidth
{
    //[[VideoEngineMgr Instance] onInnerWarning:3];
}

#pragma mark - video from network
- (void)putPacket:(unsigned char*)data Len:(int)len Ts:(unsigned int)ts
{
    // video from net
    [self NewPack:len];
    
    @autoreleasepool
    {
        [self putdata:data length:len TS:ts];
    }
}

#pragma mark - Tool funcs
- (uint32_t)putdata:(uint8_t *)data length:(uint32_t)len TS:(unsigned int)ts
{
    return [_decoder decode:data length:len timestamp:ts];
}

//
- (void)decoded:(I420VideoFrame *)avframe
{
    if(_renderFrame){
        [_renderFrame rawFrameComes:avframe];
    }
}
- (void)frameChanged:(CGSize)size
{
    if (_delegate)
    {
        [_delegate onVideoSizeChange:size Channel:self.channelid];
    }
}
@end
