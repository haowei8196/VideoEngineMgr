//
//
//  Created by whw on 16-9-7.
//  Copyright (c) 2016年  All rights reserved.
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

class I420VideoFrame;

@protocol H264DecoderDelegate<NSObject>
- (void)decoded:(I420VideoFrame*)avframe;
- (void)frameChanged:(CGSize)size;
@end

@interface H264Decoder : NSObject
{
@protected
    __weak id<H264DecoderDelegate> _delegate;
    uint8_t  *_spsppsBuf;
    int32_t   _spslen;
    int32_t   _ppslen;

    I420VideoFrame* _i420Frame;
    
    int32_t     _width;
    int32_t     _height;
}
+ (id)create;
+ (void)destroy:(H264Decoder*)decoder;
- (int)decode:(uint8_t*)data length:(int)len timestamp:(long)ts;
- (void)registerDelegate:(id)delegate;
@end
