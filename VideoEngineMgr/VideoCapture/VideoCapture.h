//
//  VideoCapture.h
//  VideoCapture
//
//  Created by whw on 16-8-27.
//  Copyright (c) 2016年 All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "VideoDefines.h"
class  NativeVideoFrame;
struct VideoCapability;

@protocol CaptureDelegate <Reporter>
- (void)rawFrame:(NativeVideoFrame*)frame Capability:(struct VideoCapability*)capability;
@end

@interface VideoCapture : NSObject
- (id)initWithDelegate:(id<CaptureDelegate>)delegate;
- (BOOL)setCaptureDeviceByPosition:(BOOL)front;
- (BOOL)setCaptureCapability:(struct VideoCapability*)capability;
- (BOOL)startCapture;
- (BOOL)stopCapture;
- (AVCaptureVideoPreviewLayer *)previewLayer;
- (void)takePicture:(int)size Complete:(void(^)(UIImage*, NSError*))complete;
@end


