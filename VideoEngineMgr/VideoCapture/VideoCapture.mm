//
//  VideoCapture.m
//  VideoCapture
//
//  Created by whw on 16-8-27.
//  Copyright (c) 2016年 All rights reserved.
//
#import <VideoCapture.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Utils.h>

#include "VideoFrame.h"
#import "VideoDefines.h"

static dispatch_queue_t captureQueue = nil;
static const char *captureQueueSpecific = "com.video.capturequeue";

@interface VideoCapture() <AVCaptureVideoDataOutputSampleBufferDelegate>
{
    __weak id<CaptureDelegate> _owner;
    VideoCapability _capability;
    AVCaptureSession* _captureSession;
    Rotation _frameRotation;
    BOOL _orientationHasChanged;
    AVCaptureConnection* _connection;
    BOOL _captureChanging;  // Guarded by _captureChangingCondition.
    NSCondition* _captureChangingCondition;
    NativeVideoFrame _videoFrame;
}
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *prevLayer;
@property (nonatomic, strong) NSDictionary *resolutionDic;
@end
@implementation VideoCapture
- (dispatch_queue_t)captureQueue
{
    if (captureQueue == NULL)
    {
        captureQueue = dispatch_queue_create(captureQueueSpecific, 0);
        
        dispatch_queue_set_specific(captureQueue, captureQueueSpecific, (void *)captureQueueSpecific, NULL);
    }
    return captureQueue;
}
- (bool)isCurrentQueueCaptureQueue
{
    return dispatch_get_specific(captureQueueSpecific) != NULL;
}
- (void)dispatchOnCaptureQueue:(dispatch_block_t)block synchronous:(bool)synchronous
{
    if ([self isCurrentQueueCaptureQueue])
    {
        @autoreleasepool
        {
            block();
        }
    }
    else
    {
        if (synchronous)
        {
            dispatch_sync([self captureQueue], ^
                          {
                              @autoreleasepool
                              {
                                  block();
                              }
                          });
        }
        else
        {
            dispatch_async([self captureQueue], ^
                           {
                               @autoreleasepool
                               {
                                   block();
                               }
                           });
        }
    }
}
- (id)initWithDelegate:(id<CaptureDelegate>)owner
{
    if (self == [super init]) {
        _owner = owner;
        _captureSession = [[AVCaptureSession alloc] init];
#if defined(__IPHONE_7_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_7_0
        NSString* version = [[UIDevice currentDevice] systemVersion];
        if ([version integerValue] >= 7) {
            _captureSession.usesApplicationAudioSession = NO;
            _captureSession.automaticallyConfiguresApplicationAudioSession = NO;
        }
#endif
        _captureChanging = NO;
        _captureChangingCondition = [[NSCondition alloc] init];
        
        if (!_captureSession || !_captureChangingCondition) {
            return nil;
        }
        
        // create and configure a new output (using callbacks)
        AVCaptureVideoDataOutput* captureOutput = [[AVCaptureVideoDataOutput alloc] init];
        NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
        
        NSNumber* val = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
        NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:val forKey:key];
        [captureOutput setVideoSettings:videoSettings];
        [captureOutput setAlwaysDiscardsLateVideoFrames:YES];
        // add new output
        if ([_captureSession canAddOutput:captureOutput]) {
            [_captureSession addOutput:captureOutput];
        } else {
            //error
        }
        
        if (!_prevLayer)
        {
            _prevLayer = [AVCaptureVideoPreviewLayer layerWithSession:_captureSession];
            _prevLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        }
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        NSNotificationCenter* notify = [NSNotificationCenter defaultCenter];
        [notify addObserver:self
                   selector:@selector(onVideoError:)
                       name:AVCaptureSessionRuntimeErrorNotification
                     object:_captureSession];
        [notify addObserver:self
                   selector:@selector(deviceOrientationDidChange:)
                       name:UIDeviceOrientationDidChangeNotification
                     object:nil];
    }
    
    return self;
}

- (void)directOutputToSelf {
    [[self currentOutput] setSampleBufferDelegate:self queue:[self captureQueue]];
}

- (void)directOutputToNil {
    [[self currentOutput] setSampleBufferDelegate:nil queue:NULL];
}
- (void)deviceOrientationDidChange:(NSNotification*)notification {
    _orientationHasChanged = YES;
    [self setRelativeVideoOrientation];
}
- (void)setRelativeVideoOrientation {
    if (!_connection.supportsVideoOrientation) {
        return;
    }
    
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationPortrait:
            _connection.videoOrientation = AVCaptureVideoOrientationPortrait;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            _connection.videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        case UIDeviceOrientationLandscapeLeft:
            _connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        case UIDeviceOrientationLandscapeRight:
            _connection.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIDeviceOrientationFaceUp:
        case UIDeviceOrientationFaceDown:
        case UIDeviceOrientationUnknown:
            if (!_orientationHasChanged) {
                _connection.videoOrientation = AVCaptureVideoOrientationPortrait;
            }
            break;
    }
    _prevLayer.connection.videoOrientation = _connection.videoOrientation;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)setCaptureDeviceByPosition:(BOOL)front
{
    [self waitForCaptureChangeToFinish];
    // check to see if the camera is already set
    
    AVCaptureDevicePosition desiredPosition = front?AVCaptureDevicePositionFront:AVCaptureDevicePositionBack;

    if (_captureSession)
    {
        NSArray* currentInputs = [NSArray arrayWithArray:[_captureSession inputs]];
        if ([currentInputs count] > 0)
        {
            AVCaptureDeviceInput* currentInput = [currentInputs objectAtIndex:0];
            if ([currentInput.device position] == desiredPosition)
            {
                return YES;
            }
        }
    }
    return [self changeCaptureInputByPosition:desiredPosition];
}
- (BOOL)setCaptureCapability:(struct VideoCapability*)capability
{
    if ((*capability) == _capability)
        return YES;
    BOOL restart = [_captureSession isRunning];
    
    if (restart)
    {
        [self stopCapture];
    }
    _capability = *capability;
    if (restart)
    {
        [self startCapture];
    }
    return YES;
}
- (BOOL)startCapture
{
    [self waitForCaptureChangeToFinish];
    if (!_captureSession) {
        return NO;
    }
    
    AVCaptureVideoDataOutput* currentOutput = [self currentOutput];
    if (!currentOutput)
        return NO;
    
    [self directOutputToSelf];
    
    _orientationHasChanged = NO;
    _captureChanging = YES;
    dispatch_async([self captureQueue], ^(void) { [self startCaptureInBackgroundWithOutput:currentOutput]; });
    return YES;
}

- (AVCaptureVideoDataOutput*)currentOutput {
    return [[_captureSession outputs] firstObject];
}

- (void)startCaptureInBackgroundWithOutput: (AVCaptureVideoDataOutput*)currentOutput {
    // begin configuration for the AVCaptureSession
    [_captureSession beginConfiguration];
    
    // take care of capture framerate now
    NSArray* sessionInputs = _captureSession.inputs;
    AVCaptureDeviceInput* deviceInput = [sessionInputs count] > 0 ? sessionInputs[0] : nil;
    AVCaptureDevice* inputDevice = deviceInput.device;
    if (inputDevice) {
        NSString* captureQuality = [self presetFromResolution:inputDevice];
        // picture resolution
        [_captureSession setSessionPreset:captureQuality];
        
        CMTime tm = CMTimeMake(1, _capability.fps);
        [inputDevice lockForConfiguration:nil];
        [inputDevice setActiveVideoMaxFrameDuration:tm];
        [inputDevice setActiveVideoMinFrameDuration:tm];
        [inputDevice unlockForConfiguration];
    }
    
    _connection = [currentOutput connectionWithMediaType:AVMediaTypeVideo];
    [self setRelativeVideoOrientation];
    
    // finished configuring, commit settings to AVCaptureSession.
    [_captureSession commitConfiguration];
    
    [_captureSession startRunning];
    [self signalCaptureChangeEnd];
}

- (void)onVideoError:(NSNotification*)notification {
    AVLogError(@"onVideoError: %@", notification);
}

- (BOOL)stopCapture {
    [self waitForCaptureChangeToFinish];
    [self directOutputToNil];
    
    if (!_captureSession) {
        return NO;
    }
    _orientationHasChanged = NO;
    _captureChanging = YES;
    dispatch_async([self captureQueue], ^(void) { [self stopCaptureInBackground]; });
    return YES;
}

- (void)stopCaptureInBackground {
    [_captureSession stopRunning];
    [self signalCaptureChangeEnd];
}
+ (int)captureDeviceCount {
    return (int)[[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
}

+ (AVCaptureDevice*)captureDeviceForPosition:(AVCaptureDevicePosition)positon
{
    for (AVCaptureDevice* device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (positon == device.position) {
            return device;
        }
    }
    
    return nil;
}
- (BOOL)changeCaptureInputByPosition:(AVCaptureDevicePosition)positon {
    BOOL restart = [_captureSession isRunning];
    if (restart)
    {
        [self stopCapture];
    }
    [self waitForCaptureChangeToFinish];
    NSArray* currentInputs = [_captureSession inputs];
    // remove current input
    if ([currentInputs count] > 0) {
        AVCaptureInput* currentInput = (AVCaptureInput*)[currentInputs objectAtIndex:0];
        
        [_captureSession removeInput:currentInput];
    }
    
    // Look for input device with the name requested (as our input param)
    // get list of available capture devices
    int captureDeviceCount = [VideoCapture captureDeviceCount];
    if (captureDeviceCount <= 0) {
        return NO;
    }
    
    AVCaptureDevice* captureDevice = [VideoCapture captureDeviceForPosition:positon];
    
    if (!captureDevice) {
        return NO;
    }
    
    // now create capture session input out of AVCaptureDevice
    NSError* deviceError = nil;
    AVCaptureDeviceInput* newCaptureInput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice
                                          error:&deviceError];
    
    if (!newCaptureInput) {
        AVLogError(@"%@",[deviceError localizedDescription]);
        //开始设备失败
        [self onError:Error_OpenCamera_Failed];
        return NO;
    }
    
    // try to add our new capture device to the capture session
    [_captureSession beginConfiguration];
    
    BOOL addedCaptureInput = NO;
    if ([_captureSession canAddInput:newCaptureInput]) {
        [_captureSession addInput:newCaptureInput];
        addedCaptureInput = YES;
    } else {
        addedCaptureInput = NO;
    }
    
    [_captureSession commitConfiguration];
    
    if (restart)
    {
        [self startCapture];
    }
    return addedCaptureInput;
}

- (void)captureOutput:(AVCaptureOutput*)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection*)connection {
    CVImageBufferRef videoFrame = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    _videoFrame.CreateFrame(videoFrame);
    
    VideoCapability tempCaptureCapability;
    tempCaptureCapability.width = _videoFrame.width();
    tempCaptureCapability.height = _videoFrame.height();
    tempCaptureCapability.fps = _capability.fps;
    
    if (_owner)
    {
        [_owner rawFrame:&_videoFrame Capability:&tempCaptureCapability];
    }
    _videoFrame.Reset();
}

- (void)signalCaptureChangeEnd {
    [_captureChangingCondition lock];
    _captureChanging = NO;
    [_captureChangingCondition signal];
    [_captureChangingCondition unlock];
}

- (void)waitForCaptureChangeToFinish {
    [_captureChangingCondition lock];
    while (_captureChanging) {
        [_captureChangingCondition wait];
    }
    [_captureChangingCondition unlock];
}
- (AVCaptureVideoPreviewLayer *)previewLayer
{
    return _prevLayer;
}
- (void)takePicture:(int)size Complete:(void(^)(UIImage*, NSError*))complete
{
    /*[self dispatchOnCaptureQueue:^{
        do {
            if (!self.imageOutput)
                break;
            
            _takingPicture = YES;
            AVCaptureConnection *videoConnection = nil;
            for (AVCaptureConnection *connection in self.imageOutput.connections) {
                for (AVCaptureInputPort *port in [connection inputPorts]) {
                    if ([[port mediaType] isEqual:AVMediaTypeVideo] ) {
                        videoConnection = connection;
                        break;
                    }
                }
                if (videoConnection) {
                    break;
                }
            }
            
            // 拍照
            NSLog(@"Picture taking");
            [self.imageOutput captureStillImageAsynchronouslyFromConnection:videoConnection completionHandler:^(CMSampleBufferRef imageSampleBuffer, NSError *error)
             {
                 UIImage *image = nil;
                 if (CMSampleBufferIsValid(imageSampleBuffer))
                 {
                     
                     // 获取图片数据
                     NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];
                     image = [[UIImage alloc] initWithData:imageData];
                 }
                 
                 dispatch_async([self captureQueue], ^{
                     
                     _takingPicture = NO;
                     
                     NSLog(@"Picture taken");
                     if (complete)
                     {
                         dispatch_async(dispatch_get_main_queue(), ^{
                             complete(image, error);
                         });
                     }
                 });
                 
             }];
            
            return;
        } while (0);
        
        if (complete)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                complete(nil, nil);
            });
        }
        
    } synchronous:false];*/
//    ios 8.3  Symbol not found: _
//    AVCaptureSessionInterruptionReasonKey
}
+ (NSDictionary *)getResolutions
{
//    AVCaptureSessionInterruptionReason
    NSMutableDictionary *dic = [[NSMutableDictionary alloc] init];
    
    for (AVCaptureDevice * videoDevice in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo])
    {
        if ([videoDevice supportsAVCaptureSessionPreset:AVCaptureSessionPreset1920x1080])
        {
            [dic setObject:AVCaptureSessionPreset1920x1080 forKey:@"1920*1080"];
        }
        if ([videoDevice supportsAVCaptureSessionPreset:AVCaptureSessionPreset1280x720])
        {
            [dic setObject:AVCaptureSessionPreset1280x720 forKey:@"1280*720"];
        }
        if ([videoDevice supportsAVCaptureSessionPreset:AVCaptureSessionPreset640x480])
        {
            [dic setObject:AVCaptureSessionPreset640x480 forKey:@"640*480"];
        }
        if ([videoDevice supportsAVCaptureSessionPreset:AVCaptureSessionPreset352x288])
        {
            [dic setObject:AVCaptureSessionPreset352x288 forKey:@"352*288"];
        }
        if ([videoDevice supportsAVCaptureSessionPreset:AVCaptureSessionPresetLow])
        {
            [dic setObject:AVCaptureSessionPresetLow forKey:@"192*144"];
        }
    }
    
    return dic;
}

+(NSArray*)sortedResolutionArray:(NSDictionary*)dic
{
    NSArray* arr = [[dic allKeys] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2){
        
        NSString* str1 = obj1;
        NSArray *listItems1 = [str1 componentsSeparatedByString:@"*"];
        int w1 = [[listItems1 objectAtIndex:0] intValue];
        int h1 = [[listItems1 objectAtIndex:1] intValue];
        
        NSString* str2 = obj2;
        NSArray *listItems2 = [str2 componentsSeparatedByString:@"*"];
        int w2 = [[listItems2 objectAtIndex:0] intValue];
        int h2 = [[listItems2 objectAtIndex:1] intValue];
        
        if (w1 > w2)
        {
            return NSOrderedDescending;
        }
        
        if (w1 < w2)
        {
            return NSOrderedAscending;
        }
        
        if (h1 > h2)
        {
            return NSOrderedDescending;
        }
        
        if (h1 < h2)
        {
            return NSOrderedAscending;
        }
        
        return NSOrderedSame;
    }];
    
    return arr;
}

- (NSString *)presetFromResolution:(AVCaptureDevice*)device
{
    if (!self.resolutionDic)
        self.resolutionDic = [VideoCapture getResolutions];
    NSString* sessionPreset = [NSString stringWithFormat:@"%d*%d",_capability.width,_capability.height];
    NSString* DesiredPreset = [self.resolutionDic objectForKey:sessionPreset];
    if(DesiredPreset && [device supportsAVCaptureSessionPreset:DesiredPreset])
    {
        //这里表示 这个设备支持此分辨率
        return DesiredPreset;
    }
    AVLogError(@"camera not support %@",sessionPreset);
    //上面没有return 说明不支持此分辨率 需要给上层提示
    [self onWarning:Warning_VideoProfile_NotSupported];
    
    NSArray* arr = [VideoCapture sortedResolutionArray:self.resolutionDic];
    for (int i = 0; i < arr.count; ++i)
    {
        if([arr objectAtIndex:i] == sessionPreset)
        {
            for(int j = 1;(i + j < arr.count || i - j >= 0); ++j)
            {
                NSString* preset = nil;
                if(i - j >= 0)
                {
                    preset = [arr objectAtIndex:i - j];
                    if([device supportsAVCaptureSessionPreset:[self.resolutionDic objectForKey:preset]])
                    {
                        return [self.resolutionDic objectForKey:preset];
                    }
                }
                if(i+j < arr.count)
                {
                    preset = [arr objectAtIndex:i + j];
                    if([device supportsAVCaptureSessionPreset:[self.resolutionDic objectForKey:preset]])
                    {
                        return [self.resolutionDic objectForKey:preset];
                    }
                }
            }
            
            break;
        }
    }
    
    return AVCaptureSessionPresetLow;
}

#pragma mark - Reporter

- (void)onWarning:(WaringCode)warning
{
    if (_owner && [_owner respondsToSelector:@selector(onWarning:)]) {
        [_owner onWarning:warning];
    }
}
- (void)onError:(ErrorCode)error
{
    if (_owner && [_owner respondsToSelector:@selector(onError:)]) {
        [_owner onError:error];
    }
}
@end

