//
//  VideoTask.h
//  aneVideo
//
//  Created by mac on 13-4-1.
//  Copyright (c) 2013年 Ib. All rights reserved.
//
#import <UIKit/UIKit.h>
#import "VideoDefines.h"
#define __MAX_MEM_CAPACITY  30
#define __MAX_REMOTE_VIDEOS 10
@class VideoRenderFrame;

@protocol VideoDelegate <Reporter>
- (void)onVideoSizeChange:(CGSize)size Channel:(NSNumber*)channel;
@end

@interface VideoBase : NSObject
{
    @protected
    VideoRenderFrame* _renderFrame;
}

@property (nonatomic, strong) NSNumber* channelid;
@property (nonatomic)        uint32_t  bandwidth;//in bps
@property (nonatomic)        int scalingType;//0：等比拉伸，1：等比拉伸占满全屏，2：不等比拉伸占满全屏
@property (nonatomic, strong) UIView *displayView;
+ (void)Initialize;
+ (NSNumber*)CreateChannel;
+ (void)ReleaseChannel:(NSNumber*)channelid;
+ (void)Destroy;

- (void)NewPack:(int)size;

- (void)pause;
- (void)resume:(UIView*)window;

- (int)StartRender:(UIView*)parentView Scaling:(int)scaling;
- (void)StopRender;

- (void)setScaling:(int)scaling;

@end
