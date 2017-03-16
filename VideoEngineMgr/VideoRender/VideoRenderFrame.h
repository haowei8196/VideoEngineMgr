//
//  VideoRenderFrame.h
//  emmsdk
//
//  Created by mac on 15-3-13.
//  Copyright (c) 2015年 ybx. All rights reserved.
//

#import <UIKit/UIKit.h>
@class AVCaptureVideoPreviewLayer;
class I420VideoFrame;
@interface VideoRenderFrame : UIView
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *prevLayer;
- (id)initWithParent:(UIView*)parent Preview:(AVCaptureVideoPreviewLayer*)prev;
- (void)setScalingType:(int)scalingType;
- (void)pause;
- (void)resume;
- (void)rawFrameComes:(I420VideoFrame*)raw;
@end
