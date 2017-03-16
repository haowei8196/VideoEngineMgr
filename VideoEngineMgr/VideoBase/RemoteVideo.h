//
//  anetest.h
//  anetest
//
//  Created by mac on 13-2-26.
//  Copyright (c) 2013年 Ib. All rights reserved.
//

#import "VideoBase.h"
@interface RemoteVideo : VideoBase

- (id)initWithDelegate:(id)delegate Channel:(NSNumber*)channel;

- (void)putPacket:(unsigned char*)data Len:(int)len Ts:(unsigned int)ts;
@end
