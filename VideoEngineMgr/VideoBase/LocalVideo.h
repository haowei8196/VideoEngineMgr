//
//  anetest.h
//  anetest
//
//  Created by mac on 13-2-26.
//  Copyright (c) 2013年 Ib. All rights reserved.
//
#import "VideoBase.h"

@protocol VideoTransport <VideoDelegate>
- (int)sendVideoData:(void*)data
              Length:(int)len
           TimeStamp:(long)ts;
@end

@interface LocalVideo : VideoBase

- (id)initWithDelegate:(id)delegate Channel:(NSNumber*)channel;

- (BOOL)isWatching;
- (void)pauseWatchSelf;
- (void)resumeWatchSelf:(UIView*)window;
- (uint32_t)startSend;
- (uint32_t)stopSend;

- (void)switchCamera;

- (void)setvideoparam:(CGSize)resolution FPS:(int)fps;

- (void)takePhoto:(int)size Complete:(void(^)(UIImage*, NSError*))complete;

- (void)destroy;

@end
