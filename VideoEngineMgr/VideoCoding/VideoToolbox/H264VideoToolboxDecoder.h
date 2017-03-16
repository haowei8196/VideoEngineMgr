//
//  H264VideoToolboxDecoder.h
//  AVSession
//
//  Created by whw on 2016/11/22.
//  Copyright © 2016年 meixin. All rights reserved.
//
#import "H264Decoder.h"
#import <CoreVideo/CVPixelBuffer.h>
@interface H264VideoToolboxDecoder : H264Decoder
- (void)decoded:(CVPixelBufferRef)pixelbuffer;
@end
