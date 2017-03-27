//
//  Util.h
//  anedecodetester
//
//  Created by mac on 13-3-20.
//  Copyright (c) 2013年 Ib. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <pthread.h>
#define MUTEX_DEFINE(lock) pthread_mutex_t _##lock
#define MUTEX_INIT(lock) pthread_mutex_init(&_##lock, NULL)
#define MUTEX_BEGIN(lock) pthread_mutex_lock(&_##lock);
#define MUTEX_END(lock) pthread_mutex_unlock(&_##lock);

#define UNUSED(arg) (void)arg

#define GETDICINT(dic, key,v) \
id value =[dic objectForKey:key];\
if ([value isKindOfClass:[NSString class]]||[value isKindOfClass:[NSNumber class]])\
{\
    v = [value intValue];\
}\
else\
{\
    v = 0;\
}

#define Big2Little32(A)   ((( (uint32_t)(A) & 0xff000000) >> 24) | \
(( (uint32_t)(A) & 0x00ff0000) >> 8)   | \
(( (uint32_t)(A) & 0x0000ff00) << 8)   | \
(( (uint32_t)(A) & 0x000000ff) << 24))

#define CreateCFDictionary(keys,values,size ) CFDictionaryCreate(NULL, keys, values, size,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);

@interface NSAutoLock:NSObject
-(id)initWithLock:(NSLock*)lock;
@end
@interface Utils : NSObject

+ (void)DumpData:(uint8_t*)data Len:(uint32_t)len;
+ (void)DumpData2:(uint8_t*)data Len:(uint32_t)len;

+ (NSUInteger)cpuFrequency;
+ (NSUInteger)cpuCount;
+ (long)now_ms;
+ (int)calcBiteRate:(int)w heght:(int)h fps:(int)fps;
+ (void)syncOnUiThread:(dispatch_block_t) block;
@end

@interface Timer : NSObject

@property (nonatomic) NSTimeInterval timeoutDate;

- (id)initWithTimeout:(NSTimeInterval)timeout repeat:(bool)repeat completion:(dispatch_block_t)completion queue:(dispatch_queue_t)queue;
- (void)start;
- (void)fireAndInvalidate;
- (void)invalidate;
- (bool)isScheduled;
- (void)resetTimeout:(NSTimeInterval)timeout;
- (NSTimeInterval)remainingTime;

@end
