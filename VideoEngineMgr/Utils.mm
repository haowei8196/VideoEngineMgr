//
//  Util.m
//  anedecodetester
//
//  Created by mac on 13-3-20.
//  Copyright (c) 2013年 Ib. All rights reserved.
//

#import "Utils.h"
#import <sys/sysctl.h>
#import <CommonCrypto/CommonDigest.h>
#import "VideoDefines.h"
@interface NSAutoLock()
@property (nonatomic, weak)NSLock*      lock;
@end
@implementation NSAutoLock

-(id)initWithLock:(NSLock*)lock
{
    self = [super init];
    if (self!=nil)
    {
        _lock = lock;
        [_lock lock];
    }
    return self;
}
-(void)dealloc
{
    [_lock unlock];
    _lock = nil;
}
@end
@interface Utils ()
{
}

@end

@implementation Utils

+ (void)DumpData:(uint8_t*)data Len:(uint32_t)len
{
    static int a = 0;
    a ++;
    AVLogInfo(@"DumpData start %d, len = %d", a, len);
    NSMutableString *strTmp = [[NSMutableString alloc] initWithCapacity:3*len + 20];
    for(int i=0;i < len;i++)
    {
        [strTmp appendFormat:@"%02X ", data[i]];
    }
    
    [strTmp appendFormat:@" THE END"];
    AVLogInfo(@"%@",strTmp);
    AVLogInfo(@"DumpData stop %d", a);
}

+ (void)DumpData2:(uint8_t*)data Len:(uint32_t)len
{
    static int a = 0;
    a ++;
    AVLogInfo(@"DumpData start %d, len = %d", a, len);
    NSMutableString *strTmp = [[NSMutableString alloc] initWithCapacity:5*len + 20];
    for(int i=0;i < len;i++)
    {
        for (int j=7;j>=0;j--)
        {
            int x = (data[i]>>j) & 0x1;
            [strTmp appendFormat:@"%01x", x];
        }
        
        [strTmp appendFormat:@" "];
    }
    
    [strTmp appendFormat:@" THE END"];
    AVLogInfo(@"%@",strTmp);
    AVLogInfo(@"DumpData stop %d", a);
}

#pragma mark sysctl utils
+ (NSUInteger) getSysInfo: (uint) typeSpecifier
{
    size_t size = sizeof(int);
    int results = 0;
    int mib[2] = {CTL_HW, static_cast<int>(typeSpecifier)};
    sysctl(mib, 2, &results, &size, NULL, 0);
    return (NSUInteger) results;
}

+ (NSUInteger) cpuFrequency
{
    return [self getSysInfo:HW_CPU_FREQ];
}

+ (NSUInteger) cpuCount
{
    return [self getSysInfo:HW_NCPU];
}

+ (long)now_ms
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000 + tv.tv_usec/1000;
}
+ (int)calcBiteRate:(int)w heght:(int)h fps:(int)fps
{
    int ret;
    int width = MAX(w, h);
    if(width < 320)
        ret = 130 * 1024;
    else if(width <= 352)
        ret = 220 * 1024;
    else if(width <= 640 )
    {
        ret = fps == 15?(480 * 1024):(750*1024);
    }
    else if(width <= 1280)
    {
        ret = fps == 15?(1024 * 1024):(1600*1024);
    }
    else
    {
        ret = fps == 15?(2000 * 1024):(3000*1024);
    }
    
    return ret;
}
+ (void)syncOnUiThread:(dispatch_block_t) block
{
    if ([NSThread isMainThread])
    {
        block();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), ^{
            block();
        });
    }
}
@end

#if TARGET_OS_IPHONE

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000 // iOS 6.0 or later
#define NEEDS_DISPATCH_RETAIN_RELEASE 0
#else                                         // iOS 5.X or earlier
#define NEEDS_DISPATCH_RETAIN_RELEASE 1
#endif

#else

#if MAC_OS_X_VERSION_MIN_REQUIRED >= 1080     // Mac OS X 10.8 or later
#define NEEDS_DISPATCH_RETAIN_RELEASE 0
#else
#define NEEDS_DISPATCH_RETAIN_RELEASE 1     // Mac OS X 10.7 or earlier
#endif

#endif

@interface Timer ()

@property (nonatomic) dispatch_source_t timer;
@property (nonatomic) NSTimeInterval timeout;
@property (nonatomic) bool repeat;
@property (nonatomic, copy) dispatch_block_t completion;
@property (nonatomic) dispatch_queue_t queue;

@end

@implementation Timer


- (id)initWithTimeout:(NSTimeInterval)timeout repeat:(bool)repeat completion:(dispatch_block_t)completion queue:(dispatch_queue_t)queue
{
    self = [super init];
    if (self != nil)
    {
        _timeoutDate = INT_MAX;
        
        _timeout = timeout;
        _repeat = repeat;
        self.completion = completion;
        self.queue = queue;
    }
    return self;
}

- (void)dealloc
{
    if (_timer != nil)
    {
        dispatch_source_cancel(_timer);
#if NEEDS_DISPATCH_RETAIN_RELEASE
        dispatch_release(_timer);
#endif
        _timer = nil;
    }
}

- (void)start
{
    _timeoutDate = CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970 + _timeout;
    
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_timeout * NSEC_PER_SEC)), _repeat ? (int64_t)(_timeout * NSEC_PER_SEC) : DISPATCH_TIME_FOREVER, 0);
    
    dispatch_source_set_event_handler(_timer, ^
                                      {
                                          if (self.completion)
                                              self.completion();
                                          if (!_repeat)
                                          {
                                              [self invalidate];
                                          }
                                      });
    dispatch_resume(_timer);
}

- (void)fireAndInvalidate
{
    if (self.completion)
        self.completion();
    
    [self invalidate];
}

- (void)invalidate
{
    _timeoutDate = 0;
    if (_timer != nil)
    {
        dispatch_source_cancel(_timer);
#if NEEDS_DISPATCH_RETAIN_RELEASE
        dispatch_release(_timer);
#endif
        _timer = nil;
    }
}

- (bool)isScheduled
{
    return _timer != nil;
}

- (void)resetTimeout:(NSTimeInterval)timeout
{
    [self invalidate];
    
    _timeout = timeout;
    [self start];
}

- (NSTimeInterval)remainingTime
{
    if (_timeoutDate < FLT_EPSILON)
        return DBL_MAX;
    else
        return _timeoutDate - (CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970);
}

@end

