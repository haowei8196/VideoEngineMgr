//
//  VideoDefines.h
//  AVSession
//
//  Created by whw on 2016/12/22.
//  Copyright © 2016年 meixin. All rights reserved.
//

#ifndef VideoDefines_h
#define VideoDefines_h
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, WaringCode) {
    Warning_Unknow,
    Warning_VideoProfile_NotSupported = 121,   //Don't support the resolution that setted. Session will automatically select the right resolution.
    Warning_HardWareEncode_NotSupported,  //Don't support hard ware encode
    Warning_HardWareDecode_NotSupported,  //Don't support hard ware decode
};

typedef NS_ENUM(NSInteger, ErrorCode) {
    Error_NoError = 0,
    Error_Failed = 1,

    Error_OpenCamera_Failed = 31,
};
typedef NS_ENUM(NSInteger, VideoProfile) {
    // res                  fps     kbps
    Video_192X144,       //15fps  140kbps
    //Video_320X240,       //15     200
    Video_352X288,       //15     220
    Video_640X480_15,    //15     480
    Video_640X480_30,    //30     750
    Video_1280X720_15,   //15     1200
    Video_1280X720_30,   //30     1600
    Video_1920X1080_15,  //15     2048
    Video_1920X1080_30,  //30     2048+1024
};

typedef NS_ENUM(NSUInteger, RenderMode) {
    Render_EqualScaling = 0,    //Preserve aspect ratio; fit within layer bounds.
    Render_Fit = 1,             // Preserve aspect ratio; fill layer bounds.
    Render_Adaptive = 2,        // Stretch to fill layer bounds.
};
enum PlaneType {
    kYPlane = 0,
    kUPlane = 1,
    kVPlane = 2,
    kNumOfPlanes = 3
};
enum Rotation {
    kRotate_0 = 0,  // No rotation.
    kRotate_90 = 90,  // Rotate 90 degrees clockwise.
    kRotate_180 = 180,  // Rotate 180 degrees.
    kRotate_270 = 270,  // Rotate 270 degrees clockwise.
};

struct VideoCapability
{
    int32_t width;
    int32_t height;
    int32_t fps;
    
    VideoCapability()
    {
        width = 0;
        height = 0;
        fps = 0;
    }
    ;
    bool operator!=(const VideoCapability &other) const
    {
        if (width != other.width)
            return true;
        if (height != other.height)
            return true;
        if (fps != other.fps)
            return true;
        return false;
    }
    bool operator==(const VideoCapability &other) const
    {
        return !operator!=(other);
    }
};

#ifdef NOLOG
#define AVLogError(frmt, ...)
#define AVLogWarn(frmt, ...)
#define AVLogInfo(frmt, ...)
#define AVLogDebug(frmt, ...)
#define AVLogVerbose(frmt, ...)
#endif

#define Version_iOS_8 ((NSFoundationVersionNumber >= NSFoundationVersionNumber_iOS_8_0) ? YES : NO)

@protocol Reporter <NSObject>
- (void)onError:(ErrorCode)err;
- (void)onWarning:(WaringCode)warning;
@end
#endif /* VideoDefines_h */
