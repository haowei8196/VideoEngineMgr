//
//  H264Encoder.h
//
//  Created by whw on 16-9-15.
//  Copyright (c) 2016年 Ib. All rights reserved.
//

#import <Foundation/Foundation.h>

class NativeVideoFrame;
struct VideoCapability;

@protocol H264EncoderDelegate<NSObject>
-(void)encoded:(void*)data length:(int)len timestamp:(long)ts;
@end

@interface H264Encoder : NSObject
{
@protected
    __weak id<H264EncoderDelegate> _delegate;
    BOOL _running;
    NSLock *_lock;
    
    struct VideoCapability* _usingParam;
    uint8_t*  _pTmpOut;
    uint8_t*  _pTmpCfg;
    int32_t   _cfgLen;
}

+ (id)create;
- (int)encode:(NativeVideoFrame*)avframe Capability:(struct VideoCapability*)capability;
- (void)registerDelegate:(id)delegate;

@end
