//
//
//  Created by skaly on 16-9-7.
//  Copyright (c) 2016年  All rights reserved.
//

#import "H264Decoder.h"
#import "H264Decoderlmpl.h"
#import "H264VideoToolboxDecoder.h"

#import "Utils.h"
#include "VideoFrame.h"
#define __MAX_MEM_CAPACITY  30
#define __MAX_REMOTE_VIDEOS 10

@interface H264Decoder ()
{
    BOOL    _droping;
    BOOL    _keyFrameFound;
    BOOL    _running;
}
@property (nonatomic, strong) NSThread        *thread;
@property (nonatomic, strong) NSCondition     *signal;
@property (nonatomic, strong) NSLock          *datalock;
@property (nonatomic, strong) NSMutableArray* dataToDecode;
@property (nonatomic, strong) NSMutableArray* dataTS;
@property (nonatomic, strong) NSLock          *lock;
@end

@implementation H264Decoder

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self createThread];
        _lock = [[NSLock alloc] init];
        _i420Frame = new I420VideoFrame();
    }
    return self;
}
- (uint32_t)stop
{
    AVLogInfo(@"StopWatch start");

    [_lock lock];
    _running = false;
    [_lock unlock];
    
    [_signal lock];
    [_signal signal];
    [_signal unlock];
    
    if (_thread)
        [_thread cancel];
    _thread = nil;
    _signal = nil;
    
    [_datalock lock];
    _dataToDecode = nil;
    _dataTS = nil;
    [_datalock unlock];
    _datalock = nil;
    
    [self finiDecoder];
    if (_spsppsBuf) {
        free(_spsppsBuf);
        _spsppsBuf = 0;
    }
    delete _i420Frame;
    _i420Frame = 0;

    AVLogInfo(@"StopWatch end");
    return 0;
}

- (void)createThread
{
    _keyFrameFound = false;
    _droping = YES;
    _running = true;
    _signal         = [[NSCondition alloc] init];
    NSLock *datalock = [[NSLock alloc] init];
    _datalock = datalock;
    if(_dataToDecode == nil)
    {
        _dataToDecode = [[NSMutableArray alloc] initWithCapacity:__MAX_MEM_CAPACITY];
        _dataTS = [NSMutableArray arrayWithCapacity:__MAX_MEM_CAPACITY];
    }
    
    NSThread *thread = [[NSThread alloc] initWithTarget:self selector:@selector(Threadfunc) object:nil];
    _thread = thread;
    [_thread setName:@"videoDecoderThread"];
    [_thread start];
}
+ (void)destroy:(H264Decoder*)decoder
{
    [decoder stop];
    decoder = nil;
}
+ (id)create
{
    if (Version_iOS_8) {
        H264VideoToolboxDecoder *decoder = [[H264VideoToolboxDecoder alloc] init];
        return decoder;
    }
    else
    {
        H264Decoderlmpl *decoder = [[H264Decoderlmpl alloc] init];
        return decoder;
    }
}

- (int)decode:(uint8_t*)data length:(int)len timestamp:(long)ts
{
    NSAutoLock* autolock = [[NSAutoLock alloc] initWithLock:_lock];
    UNUSED(autolock);
    if (!_running)
        return 0;
    
    if(_droping)
    {
        if (data[0] != 0x17)
        {
            return 0;
        }
        else
        {
            _droping = NO;
        }
    }
    
    [_datalock lock];
    
    if (data[0] == 0x17 && data[1] == 0)
    {
        [_dataToDecode removeAllObjects];
        [_dataTS removeAllObjects];
    }
    
    NSData *newData = [NSData dataWithBytes:data length:len];
    [_dataToDecode addObject:newData];
    [_dataTS addObject:@(ts)];
    
    [_signal lock];
    [_signal signal];
    [_signal unlock];
    [_datalock unlock];
    return 0;
}

- (void)Threadfunc
{
    _spsppsBuf = (uint8_t*)malloc(256);
    while (_running)
    {
        [_signal lock];
        [_signal wait];
        [_signal unlock];
        while (_running)
        {
            @autoreleasepool
            {
                NSData* tmpData = nil;
                NSNumber* tmpTS = nil;
                [_datalock lock];
                if(_dataToDecode.count > 0)
                {
                    tmpData = [_dataToDecode objectAtIndex:0];
                    [_dataToDecode removeObjectAtIndex:0];
                    
                    tmpTS = [_dataTS objectAtIndex:0];
                    [_dataTS removeObjectAtIndex:0];
                }
                [_datalock unlock];
                
                if(!tmpData)
                    break;
                
                if(!_running)
                    break;
                uint8_t* data = (uint8_t*)tmpData.bytes;
                
                if(data[0] == 0x17 && data[1] == 0x00)
                {
                    //Discribe Frame
                    AVLogInfo(@"sps length %lu", (unsigned long)tmpData.length);
                    u_short spslen1 = 0;
                    memcpy(&spslen1, data+11, 2);
                    
                    int spslen = ntohs(spslen1);
                    
                    data[9] = 0x00;
                    data[10]= 0x00;
                    data[11]= 0x00;
                    data[12]= 0x01;
                    
                    int ppsPos = 12+spslen;
                    
                    u_short ppslen1 = 0;
                    memcpy(&ppslen1, data+ppsPos+2, 2);
                    
                    int ppslen = ntohs(ppslen1);
                    
                    if (4 + spslen + 4 + ppslen > 256)
                    {
                        break;
                    }
                    
                    memcpy(_spsppsBuf, data+9, 4+spslen);
                    memcpy(_spsppsBuf+4+spslen, data+9, 4);
                    memcpy(_spsppsBuf+4+spslen+4, data+ppsPos+4, ppslen);
                    
                    _spslen = spslen;
                    _ppslen = ppslen;
                    if ([self checkDecoder])
                    {
                        [_delegate frameChanged:CGSizeMake(_width, _height)];
                    }
                    break;
                }
                if (data[0] == 0x17 && data[1] == 0x01)
                    _keyFrameFound = true;
                
                if (!_keyFrameFound)
                    break;
//                AVLogInfo(@"%lu", (unsigned long)tmpData.length);
                [self realDecode:(uint8_t*)tmpData.bytes length:(int)tmpData.length TS:[tmpTS intValue]];
                
                if (((uint8_t*)tmpData.bytes)[0] != 0x17 || ((uint8_t*)tmpData.bytes)[1] != 0)
                {
                    [NSThread sleepForTimeInterval:0.015f];
                }
                tmpData = nil;
                tmpTS   = nil;
            }
        }
    }
}
- (BOOL)initDecoder
{
    AVLogError(@"if you not override this method, you will get a exception");
    [self doesNotRecognizeSelector:_cmd];
    return false;
}
- (void)finiDecoder
{
    [self doesNotRecognizeSelector:_cmd];
}
- (BOOL)checkDecoder
{
    [self doesNotRecognizeSelector:_cmd];
    return FALSE;
}
- (void)realDecode:(uint8_t *)data length:(uint32_t)len TS:(unsigned int)ts
{
    [self doesNotRecognizeSelector:_cmd];
}
- (void)registerDelegate:(id)delegate
{
    _delegate = delegate;
}
@end
 
