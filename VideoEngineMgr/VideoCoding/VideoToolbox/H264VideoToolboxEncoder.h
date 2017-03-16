//
//  H264VideoToolboxEncoder.h
//  AVSession
//
//  Created by whw on 2016/11/22.
//  Copyright © 2016年 meixin. All rights reserved.
//

#import "H264Encoder.h"
#import <VideoToolbox/VideoToolbox.h>
@interface H264VideoToolboxEncoder : H264Encoder
-(void)encoded:(CMSampleBufferRef)sampleBuffer status:(OSStatus)status flags:(VTEncodeInfoFlags)infoFlags;
@end
