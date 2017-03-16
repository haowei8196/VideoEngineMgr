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
#import "LocalVideo.h"
#import "VideoCapture.h"
#import "H264Encoder.h"
#import "Utils.h"
#import "VideoEngineMgr.h"

#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "VideoDefines.h"
#include "libyuv.h"
#import "VideoRenderFrame.h"
#define LIVE_START_INCREASE_INTERVAL 10
#define H264DROPPINGCFG_MAXCAPS	3

@interface LocalVideo ()<CaptureDelegate,H264EncoderDelegate>
{
    BOOL    _watching;
    BOOL    _sending;
    BOOL    _pause;
    Boolean _useFrontCamera;
    
    int  _curW;
    int  _curH;
    struct VideoCapability _capability;
}

@property (nonatomic, strong) VideoCapture *videoStream;
@property (nonatomic, strong) H264Encoder *encoder;
@property (nonatomic, weak) id<VideoTransport> delegate;
@property (nonatomic, strong) UIView *displayView;
@end

@implementation LocalVideo

#pragma mark - Outlets
- (id)initWithDelegate:(id)delegate Channel:(NSNumber*)channel
{
    self = [super init];
    if(self)
    {
        _delegate = delegate;
        _watching = NO;
        _sending = NO;
        _useFrontCamera = true;
        self.channelid = channel;
        _capability.fps = 15;
        _capability.width = 352;
        _capability.height = 288;

        _curW = 0;
        _curH = 0;
    }
    return self;
}


-(void)dealloc
{
    _delegate = nil;
    self.videoStream = nil;
}

- (void)destroy
{
    [self StopCapture];
    [self StopSender];
}
- (int)StartRender:(UIView *)parentView Scaling:(int)scaling
{
    int res = 0;
    res = [self StartCapture:_useFrontCamera];
    if (parentView) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            _renderFrame = [[VideoRenderFrame alloc] initWithParent:parentView Preview:_videoStream.previewLayer];
            [_renderFrame setScalingType:scaling];
        });
    }
    //[_videoStream Preview:window];
    _watching = YES;
    return res;
}
- (void)StopRender
{
    _watching = NO;
    //[_videoStream StopPreview];
    dispatch_sync(dispatch_get_main_queue(), ^{
        [_renderFrame removeFromSuperview];
        _renderFrame = nil;
    });
    [self CheckIfNeedToStop];
}
- (BOOL)isWatching
{
    return _watching;
}
- (void)pauseWatchSelf
{
    //[_videoStream StopPreview];
}

- (void)resumeWatchSelf:(UIView*)window
{
    if (_videoStream != nil && _watching)
    {
//        [_videoStream Preview:window];
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
}

- (uint32_t)startSend
{
    [self StartSender];
    
    //if(!self.videoStream)
    //{
        [self StartCapture:_useFrontCamera];
    //}
//    else
//    {
//        [self changeCamera:_useFrontCamera];
//    }
    _sending = YES;
    return 0;
}

- (uint32_t)stopSend
{
    _sending = NO;
    [self StopSender];
    [self CheckIfNeedToStop];
    return 0;
}
- (void)switchCamera
{
    [self changeCamera:!_useFrontCamera];
}
- (void)changeCamera:(Boolean)isFront
{
    if(_useFrontCamera == isFront)
    {
        return;
    }
    _useFrontCamera = isFront;
    
    if (!self.videoStream)
    {
        return;
    }
    [_videoStream setCaptureDeviceByPosition:_useFrontCamera];
}

- (void)setvideoparam:(CGSize)resolution FPS:(int)fps
{
    struct VideoCapability capability;
    capability.fps = fps;
    capability.height = (int)resolution.height;
    capability.width = (int)resolution.width;
    
    if (capability == _capability)
        return;
    _capability = capability;
    if(self.videoStream)
    {
        [self.videoStream setCaptureCapability:&_capability];
    }
}

#pragma mark - CaptureDelegate
- (void)rawFrame:(NativeVideoFrame*)frame Capability:(struct VideoCapability*)capability
{
    if (_encoder && _sending) {
        [_encoder encode:frame Capability:capability];
    }
    if (capability->width != _curW || capability->height != _curH)
    {
        _curW = capability->width;
        _curH = capability->height;
        [_delegate onVideoSizeChange:CGSizeMake(_curW, _curH) Channel:self.channelid];
    }
}
- (void)onWarning:(WaringCode)warning
{
    if (_delegate && [_delegate respondsToSelector:@selector(onWarning:)]) {
        [_delegate onWarning:warning];
    }
}
- (void)onError:(ErrorCode)error
{
    if (_delegate && [_delegate respondsToSelector:@selector(onError:)]) {
        [_delegate onError:error];
    }
}

#pragma mark - H264EncoderDelegate
-(void)encoded:(void *)data length:(int)len timestamp:(long)ts
{
    if (_delegate)
    {
        [_delegate sendVideoData:data Length:len TimeStamp:ts];
    }
}

#pragma mark - Tool funcs
- (int)StartCapture:(Boolean)useFrontCamera
{
    int res = 0;
    
    _useFrontCamera = useFrontCamera;
    
    if(_pause)
        return res;
    
    if(!self.videoStream)
    {
        // VideoStream
        VideoCapture *stream =[[VideoCapture alloc] initWithDelegate:self];
        self.videoStream = stream;
        //todo whw
    }
    [self.videoStream setCaptureCapability:&_capability];
    [self.videoStream setCaptureDeviceByPosition:_useFrontCamera];
    [self.videoStream startCapture];
    return res;
}

- (void)StopCapture
{
    if(!self.videoStream)
        return;
    
    [self.videoStream stopCapture];
    //self.videoStream = nil;
}
- (void)StartSender
{
    AVLogInfo(@"StartSender start");
    if(self.encoder != nil)
        return;
    
    //Sender
    H264Encoder *encoder = [H264Encoder create];
    [encoder registerDelegate:self];
    self.encoder = encoder;

    if ([NSStringFromClass(self.encoder.class) isEqualToString:@"H264EncoderImpl"]) {//
        [self.delegate onWarning:Warning_HardWareEncode_NotSupported];
    }
    
    AVLogInfo(@"StartSender stop");
}

- (void)StopSender
{
    AVLogInfo(@"StopSender start");
    
    if(self.encoder)
    {
        self.encoder = nil;
    }
    
    AVLogInfo(@"StopSender stop");
}

- (void)CheckIfNeedToStop
{
    if (!_sending && !_watching)
    {
        [self StopCapture];
    }
}


- (void)takePhoto:(int)size Complete:(void(^)(UIImage*, NSError*))complete
{
    if (_videoStream)
    {
        [_videoStream takePicture:size Complete:complete];
    }
}

@end
