//
//  VideoEngineMgr.h
//
//  Created by whw on 17-3-10.
//  Copyright (c) 2017年 itcast. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "VideoDefines.h"
@protocol VideoEngineMgrDelegate <Reporter>
- (void)sendVideoData:(uint8_t*)data Length:(int)len TimeStamp:(long)ts;
- (void)onVideoSizeChanged:(CGSize)size Uid:(int)uid;
@end

@interface VideoEngineMgr : NSObject

@property (nonatomic) NSUInteger receive_bytes_video;
@property (nonatomic) NSUInteger send_bytes_video;

+ (VideoEngineMgr*)Instance;
+ (void)Destroy;

- (void)initialize:(int)uid Delegate:(id)delegate;
- (void)clear;


- (int)playVideo:(int)uid Window:(UIView*)window Scaling:(int)scaling;
- (void)unPlayVideo:(int)uid;


- (void)receivedPacket:(int)uid Data:(unsigned char*)data Length:(int)len TimeStamp:(unsigned int)ts;


- (uint32_t)startSend;
- (void)stopSend;

- (void)swichCamera;
- (int)updateRenderView:(int)uid window:(UIView *)view;
- (void)setVideoParam:(CGSize)resolution FPS:(int)fps;

//拍照
- (void)takePhoto:(int)size Complete:(void(^)(UIImage*, NSError*))complete;
@end
