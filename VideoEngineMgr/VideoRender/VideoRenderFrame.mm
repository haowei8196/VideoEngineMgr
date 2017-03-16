//
//  VideoRenderFrame.m
//  emmsdk
//
//  Created by mac on 15-3-13.
//  Copyright (c) 2015年 ybx. All rights reserved.
//

#import "VideoRenderFrame.h"
#import "VideoRenderIosView.h"

#import <AVFoundation/AVFoundation.h>
@interface VideoRenderFrame ()
{
    CGSize    _curVideoSize;
    CGSize    _curBoundSize;
    BOOL      _pause;
    I420VideoFrame frame;
    BOOL        _renderInited;
}

@property (nonatomic, strong) VideoRenderIosView* renderView;

@property (nonatomic, strong) NSLock* lock;
@property (nonatomic)         int scalingType;//0：等比拉伸，1：等比拉伸占满全屏，2：不等比拉伸占满全屏
@end
@implementation VideoRenderFrame

- (id)initWithParent:(UIView*)view Preview:(AVCaptureVideoPreviewLayer*)prev
{
    self = [super initWithFrame:view.bounds];
    if (self) {
        
        self.backgroundColor = [UIColor blackColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.clipsToBounds = YES;
        [view addSubview:self];
        [view setAutoresizesSubviews:YES];
        
        _lock = [[NSLock alloc] init];
        
        if (prev)
        {
            _prevLayer = prev;
            _prevLayer.frame = [self bounds];
            [self.layer addSublayer:_prevLayer];
        }
        
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(willResignActive)
                                   name:UIApplicationWillResignActiveNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(didBecomeActive)
                                   name:UIApplicationDidBecomeActiveNotification
                                 object:nil];
    }
    return self;
}
- (void)dealloc
{
    [_lock lock];
    _renderView = nil;
    [_lock unlock];
    if (_prevLayer){
        [_prevLayer removeFromSuperlayer];
    }
    _prevLayer = nil;
    _lock = nil;
    
}
- (void)setScalingType:(int)scaling
{
    if(_scalingType == scaling)
        return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        _scalingType = scaling;
        _curVideoSize = CGSizeMake(0, 0);
        if (_prevLayer)
        {
            switch (_scalingType){
                case 0: 
                    _prevLayer.videoGravity = AVLayerVideoGravityResizeAspect;
                    break;
                case 1: 
                    _prevLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
                    break;
                default: 
                    _prevLayer.videoGravity = AVLayerVideoGravityResize;
                    break;
            }
        }

    });
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    //_curBoundSize = self.bounds.size;
    if (_prevLayer != nil)
    {
        _prevLayer.frame = [self bounds];
    }
    else
    {
        [self reCalulateFrame];
    }
}
- (void)reCalulateFrame
{
    CGSize curBoundSize = self.bounds.size;
    float realW = curBoundSize.width;
    float realH = curBoundSize.height;
    float w = _curVideoSize.width;
    float h = _curVideoSize.height;
    
    if(realW == 0 || realH == 0 || w == 0 || h == 0)
        return;
    
    switch (_scalingType) {
        case 0:
        {
            if(w / h > curBoundSize.width / curBoundSize.height)
            {
                realH = realW * h / w;
            }
            else
            {
                realW = realH * w / h;
            }
        }
            break;
        case 1:
        {
            if(w / h > curBoundSize.width / curBoundSize.height)
            {
                realW = realH * w / h;
            }
            else
            {
                realH = realW * h / w;
            }
        }
            break;
        default:
            break;
    }
    
    if(!_renderView)
        [self getRenderView:self Frame:CGRectMake(0, 0, realW, realH)];
    else
    {
        if(!_renderView.superview)
        {
            [self addSubview:_renderView];
        }
        [_renderView setFrame:CGRectMake(0, 0, realW, realH)];
    }
    if (!_renderInited)
    {
        _renderInited = [_renderView createContext];
    }
    
    [_renderView setCenter:CGPointMake(curBoundSize.width/2, curBoundSize.height/2)];
    [_renderView setHidden:NO];
    
    AVLogInfo(@"reCalulateFrame %f, %f, %f, %f, %f, %f", curBoundSize.width, curBoundSize.height, w, h, _renderView.frame.size.width, _renderView.frame.size.height);
}

- (void)rawFrameComes:(I420VideoFrame*)_raw
{
    if (!_raw)
    {
        return;
    }
    
    float w = _raw->width();
    float h = _raw->height();
    if (!w || !h)
    {
        return;
    }
    
    
    frame.CreateFrame(_raw->buffer(kYPlane),
                      _raw->buffer(kUPlane),
                      _raw->buffer(kVPlane),
                      _raw->width(), _raw->height(),
                      _raw->stride(kYPlane),
                      _raw->stride(kUPlane),
                      _raw->stride(kVPlane));
    
    CGSize sz = [self bounds].size;
    if(sz.width == 0 || sz.height == 0 || w == 0 || h == 0)
        return;
    
    if(_curVideoSize.width != w || _curVideoSize.height != h || sz.width != _curBoundSize.width || sz.height != _curBoundSize.height)
    {
        dispatch_sync(dispatch_get_main_queue(), ^{
            _curBoundSize = [self bounds].size;
            _curVideoSize = CGSizeMake(w, h);
            [self reCalulateFrame];
            [_renderView resetViewport];
        });
    }
    
    if(_pause)
        return;
    
    [_lock lock];
    
    if (!_pause && _renderView)
    {
        [_renderView renderFrame:&frame];
        [_renderView presentFramebuffer];
    }
    
    [_lock unlock];
}
- (void)pause
{
    [_lock lock];
    
    _pause = YES;
    
    [_lock unlock];
}
- (void)resume
{
    [_lock lock];
    
    _pause = NO;
    
    [_lock unlock];
}
- getRenderView:(UIView*)parentView Frame:(CGRect)f
{
    VideoRenderIosView *renderView = nil;
    renderView = [[VideoRenderIosView alloc] initWithFrame:f];
    [parentView addSubview:renderView];
    
    [_lock lock];
    _renderView = renderView;
    [_lock unlock];
    return renderView;
}
- (void)didBecomeActive {
    [self resume];
}

- (void)willResignActive {
    [self pause];
}

@end
