//
//  anetest.m
//  anetest
//
//  Created by mac on 13-2-26.
//  Copyright (c) 2013年 Ib. All rights reserved.
//

#import "VideoEngineMgr.h"
#import "RemoteVideo.h"
#import "LocalVideo.h"
#import "Utils.h"
@interface VideoEngineMgr ()<VideoTransport>
{
    int     _uid;
}

@property (nonatomic, strong) LocalVideo *localvideo;
@property (nonatomic, strong) NSMutableDictionary*    remotevideos;
@property (nonatomic, assign) id<VideoEngineMgrDelegate> delegate;
@property (nonatomic, strong) NSLock*                remotevideoLock;
@property (nonatomic) CGSize videoSize;
@property (nonatomic) int videoFPS;
@end

VideoEngineMgr *VideoEngineMgrInstance = nil;
@implementation VideoEngineMgr

#pragma mark - Outlets
+ (VideoEngineMgr*)Instance
{
    if (!VideoEngineMgrInstance)
    {
        VideoEngineMgrInstance = [[VideoEngineMgr alloc] init];
        VideoEngineMgrInstance.videoSize = CGSizeZero;
        VideoEngineMgrInstance.videoFPS = 0;
        [VideoBase Initialize];
    }
    
    return VideoEngineMgrInstance;
}

+ (void)Destroy
{
    [VideoEngineMgrInstance clear];
    [VideoBase Destroy];
    VideoEngineMgrInstance = nil;
}


-(id)init
{
    self = [super init];
    if (self)
    {
        _uid = 0;
        
        _remotevideoLock = [[NSLock alloc] init];
        _remotevideos = [[NSMutableDictionary alloc] initWithCapacity:__MAX_REMOTE_VIDEOS];
        _receive_bytes_video = 0;
        _send_bytes_video = 0;
    }
    return self;
}

- (void)dealloc
{
    _remotevideos = nil; 
    _remotevideoLock = nil;
}

- (void)initialize:(int)uid Delegate:(id)delegate
{
    [self clear];
    
    _delegate = delegate;
    _uid = uid;
    
    NSNumber* channelid = [VideoBase CreateChannel];
    
    _localvideo = [[LocalVideo alloc] initWithDelegate:self Channel:channelid];
}

- (void)clear
{
    AVLogInfo(@"VideoEngineMgr Finalize");
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    _delegate = nil;
    
    if(_localvideo)
    {
        [_localvideo destroy];
        _localvideo = nil;
    }
    NSArray* remotes = nil;
    [_remotevideoLock lock];
    remotes = [_remotevideos allKeys];
    [_remotevideoLock unlock];
    if ([remotes count] > 0)
    {
        for (NSNumber* key in remotes)
        {
            [self unPlayVideo:[key intValue]];
        }
    }
}
- (int)getUidByChannel:(NSNumber*)channel
{
    NSAutoLock* lock = [[NSAutoLock alloc] initWithLock:_remotevideoLock];
    UNUSED(lock);

    int uid = 0;
    for (NSNumber* key in [_remotevideos allKeys])
    {
        RemoteVideo* task = [_remotevideos objectForKey:key];
        if ([task.channelid intValue] == [channel intValue])
            uid = [key intValue];
    }
    return uid;
}
- (RemoteVideo*)getRemoteVideo:(int)uid
{
    NSAutoLock* lock = [[NSAutoLock alloc] initWithLock:_remotevideoLock];
    UNUSED(lock);
    RemoteVideo* task = [_remotevideos objectForKey:@(uid)];
    return task;
}
- (RemoteVideo*)createRemoteVideo:(int)uid Channel:(NSNumber*)channel
{
    NSAutoLock* lock = [[NSAutoLock alloc] initWithLock:_remotevideoLock];
    UNUSED(lock);
    
    RemoteVideo* task = [[RemoteVideo alloc] initWithDelegate:self Channel:channel];
    [_remotevideos setObject:task forKey:@(uid)];
    return task;
}
- (void)deleteRemoteVideo:(int)uid
{
    NSAutoLock* lock = [[NSAutoLock alloc] initWithLock:_remotevideoLock];
    UNUSED(lock);
    RemoteVideo* task = [_remotevideos objectForKey:@(uid)];
    if (task)
        [_remotevideos removeObjectForKey:@(uid)];
    task = nil;
}
- (void)receivedPacket:(int)uid Data:(unsigned char*)data Length:(int)len TimeStamp:(unsigned int)ts
{
    RemoteVideo* task = nil;
    {
        NSAutoLock* lock = [[NSAutoLock alloc] initWithLock:_remotevideoLock];
        UNUSED(lock);
        task = [_remotevideos objectForKey:@(uid)];
        _receive_bytes_video += len;
    }
    if(task != nil)
    {
        [task putPacket:data Len:len Ts:ts];
    }
}

- (int)playVideo:(int)uid Window:(UIView*)window RenderMode:(RenderMode)mode
{
    if (uid == _uid)
    {
        if (_localvideo && _localvideo.isWatching)
        {
            return [_localvideo.channelid intValue];
        }
        if (_videoFPS != 0 && _videoSize.width != 0 && _videoSize.height != 0) {
            [self setVideoParam:_videoSize FPS:_videoFPS];
        }
        if ([_localvideo StartRender:window Scaling:mode] == -1)
            return -1;
        return [_localvideo.channelid intValue];
    }
    else
    {
        RemoteVideo* task = [self getRemoteVideo:uid];
        if(task != nil)
        {
            return [[task channelid] intValue];
        }
        
        NSNumber* channelid = [VideoBase CreateChannel];
        if(!channelid)
            return -1;
        
        task = [self createRemoteVideo:uid Channel:channelid];
        if(!task) {
            [VideoBase ReleaseChannel:channelid];
            return -1;
        }
        if ([task StartRender:window Scaling:mode] == -1)
            return -1;
        return [channelid intValue];
    }
}

- (void)unPlayVideo:(int)uid
{
    if(uid == _uid)
    {
        if (_localvideo && _localvideo.isWatching)
        {
            [_localvideo StopRender];
        }
    }
    else
    {
        RemoteVideo* task = [self getRemoteVideo:uid];
        
        if (task == nil) return;
        [task StopRender];
        [VideoBase ReleaseChannel:task.channelid];
        [self deleteRemoteVideo:uid];
    }
}



- (uint32_t)startSend
{
    return [self.localvideo startSend];
}

- (void)stopSend
{
    [_localvideo stopSend];
}


- (void)swichCamera
{
    [_localvideo switchCamera];
}

- (int)updateRenderView:(int)uid window:(UIView *)view
{
    VideoBase* video = nil;
    if (_uid == uid) {
        video = _localvideo;
    } else {
        video = [self getRemoteVideo:uid];
    }
    if (video)
    {
        [video resume:view];
        return [video.channelid intValue];
    }
    return -1;
}
- (void)setVideoProfile:(VideoProfile)profile
{
    CGSize size = CGSizeZero;
    int fps = 15;
    switch (profile) {
        case Video_192X144:
        {
            size = CGSizeMake(192, 144);
            fps = 15;
        } break;
        case Video_352X288:
        {
            size = CGSizeMake(352, 288);
            fps = 15;
        } break;
        case Video_640X480_15:
        {
            size = CGSizeMake(640, 480);
            fps = 15;
        } break;
        case Video_640X480_30:
        {
            size = CGSizeMake(640, 480);
            fps = 30;
        } break;
        case Video_1280X720_15:
        {
            size = CGSizeMake(1280, 720);
            fps = 15;
        } break;
        case Video_1280X720_30:
        {
            size = CGSizeMake(1280, 720);
            fps = 30;
        } break;
        case Video_1920X1080_15:
        {
            size = CGSizeMake(1920, 1080);
            fps = 15;
        } break;
        case Video_1920X1080_30:
        {
            size = CGSizeMake(1920, 1080);
            fps = 30;
        } break;
        default:
        {
            size = CGSizeMake(352, 288);
            break;
        }
    }
    AVLogInfo(@"Resolution: %@ FPS: %d", NSStringFromCGSize(resolution), fps);
    
    [self setVideoParam:size FPS:fps];
}
- (void)setVideoParam:(CGSize)resolution FPS:(int)fps
{
    AVLogInfo(@"Resolution: %@ FPS: %d", NSStringFromCGSize(resolution), fps);
    
    if (_localvideo) {
        [_localvideo setvideoparam:resolution FPS:fps];
        _videoSize = CGSizeZero;
        _videoFPS = 0;
    } else {
        _videoSize = resolution;
        _videoFPS = fps;
    }
}

- (void)takePhoto:(int)size Complete:(void(^)(UIImage*, NSError*))complete
{
    [_localvideo takePhoto:size Complete:complete];
}


- (void)onWarning:(WaringCode)warning
{
    if (_delegate && [_delegate respondsToSelector:@selector(onWarning:)]) {
        [_delegate onWarning:warning];
    }
}
- (void)onError:(ErrorCode)error
{
    if (_delegate && [_delegate respondsToSelector:@selector(onError:)]) {
        [_delegate onError:error];
    }
}
- (int)sendVideoData:(void*)data Length:(int)len TimeStamp:(long)ts
{
    if (_delegate) {
        _send_bytes_video += len;
        [_delegate sendVideoData:(uint8_t*)data Length:len TimeStamp:[Utils now_ms]];
    }
    return 0;
}

- (void)onVideoSizeChange:(CGSize)size Channel:(NSNumber *)channel
{
    if (_delegate)
    {
        int uid = 0;
        if ([channel intValue] == [_localvideo.channelid intValue])
            uid = _uid;
        else
            uid = [self getUidByChannel:channel];
        [_delegate onVideoSizeChanged:size Uid:uid];
    }
}

- (uint32_t)getbandwidth:(NSString*)path
{
    if(path == nil)
        return _localvideo.bandwidth;

    VideoBase* task = [_remotevideos objectForKey:path];
    if(task)
    {
        return task.bandwidth;
    }

    return 0;
}
#pragma mark - Tools
@end
