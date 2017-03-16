//
//  H264Encoder.m
//
//  Created by whw on 16-9-15.
//  Copyright (c) 2016年 Ib. All rights reserved.
//

#import "H264Encoder.h"
#import "libavformat/avformat.h"
#import "H264Decoderlmpl.h"
#import "H264EncoderImpl.h"
#import "H264VideoToolboxEncoder.h"

#include "VideoDefines.h"
#import "Utils.h"


#define AbstractMethodNotImplemented() \
@throw [NSException exceptionWithName:NSInternalInconsistencyException \
                               reason:[NSString stringWithFormat:@"You must override %@ in a subclass.", NSStringFromSelector(_cmd)] \
                             userInfo:nil]



@interface H264Encoder ()


@end

@implementation H264Encoder


+ (id)create
{
    if (Version_iOS_8) {
        H264VideoToolboxEncoder *encoder = [[H264VideoToolboxEncoder alloc] init];
        return encoder;
    } else
    {
        H264EncoderImpl *encoder = [[H264EncoderImpl alloc] init];
        return encoder;
    }
    return nil;
}
- (id)init
{
    self = [super init];
    if (self)
    {
        _usingParam = (struct VideoCapability*)malloc(sizeof(struct VideoCapability));
        memset(_usingParam,0,sizeof(struct VideoCapability));
        _pTmpCfg = 0;
        _pTmpOut = 0;
        _cfgLen = 0;
        _running = YES;
        _lock = [[NSLock alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [_lock lock];
    _running = NO;
    [_lock unlock];
    [self finiEncoder];
    if (_pTmpOut)
    {
        free(_pTmpOut);
        _pTmpOut = 0;
    }
    if (_pTmpCfg)
    {
        free(_pTmpCfg);
        _pTmpCfg = 0;
    }
    if (_usingParam)
    {
        free(_usingParam);
        _usingParam = 0;
    }
}
- (void)registerDelegate:(id)delegate
{
    _delegate = delegate;
}
- (int)encode:(NativeVideoFrame*)avframe Capability:(struct VideoCapability*)capability
{
    NSAutoLock* autolock = [[NSAutoLock alloc] initWithLock:_lock];
    UNUSED(autolock);
    if (!_running)
        return 0;
    [self checkEncoder:capability];
    
    return [self realEncode:avframe TimeStamp:[Utils now_ms]];
}

- (int)checkEncoder:(struct VideoCapability*)capability
{
    if((*capability)!=(*_usingParam))
    {
        memcpy(_usingParam,capability,sizeof(struct VideoCapability));
        [self finiEncoder];
        if (_pTmpOut)
        {
            free(_pTmpOut);
            _pTmpOut = 0;
        }
        [self initEncoder];
        
        if (!_pTmpCfg)
            _pTmpCfg = (uint8_t*)malloc(100);
        if (!_pTmpOut)
            _pTmpOut = (uint8_t*)malloc(_usingParam->width * _usingParam->height * 2 + 100);
    }
    return 0;
}
- (BOOL)initEncoder
{
    AVLogError(@"if you not override this method, you will get a exception");
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}
- (void)finiEncoder
{
    [self doesNotRecognizeSelector:_cmd];
}
- (int)realEncode:(NativeVideoFrame *)avFrame TimeStamp:(long)ts
{
    [self doesNotRecognizeSelector:_cmd];
    return -1;
}
@end
