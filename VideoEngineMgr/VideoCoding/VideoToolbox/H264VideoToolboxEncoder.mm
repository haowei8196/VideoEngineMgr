//
//  H264VideoToolboxEncoder.m
//  AVSession
//
//  Created by whw on 2016/11/22.
//  Copyright © 2016年 meixin. All rights reserved.
//

#import "H264VideoToolboxEncoder.h"
#import <UIKit/UIKit.h>
#import "Utils.h"
#import "libyuv.h"
#include "VideoDefines.h"
#include "VideoFrame.h"

const float kLimitToAverageBitRateFactor = 1.5f; // 2.0f
static OSType KVideoPixelFormatType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;

CVPixelBufferRef createCVPixelBuffer(NativeVideoFrame* buffer)
{
    CFDictionaryRef pixelBufferAttributes = CreateCFDictionary(nil,nil,0);
    
    CVPixelBufferRef pixelBuffer;
    CVPixelBufferCreate(NULL, buffer->width(), buffer->height(), KVideoPixelFormatType, pixelBufferAttributes, &pixelBuffer);
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    
    uint8_t* dst_y = reinterpret_cast<uint8_t*>(
                                                CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0));
    int dst_stride_y = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    uint8_t* dst_uv = reinterpret_cast<uint8_t*>(
                                                 CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1));
    int dst_stride_uv = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    // Convert I420 to NV12.
    libyuv::I420ToNV12(buffer->buffer(kYPlane), buffer->stride(kYPlane),
                                 buffer->buffer(kUPlane), buffer->stride(kUPlane),
                                 buffer->buffer(kVPlane), buffer->stride(kVPlane),
                                 dst_y, dst_stride_y, dst_uv, dst_stride_uv,
                                 buffer->width(), buffer->height());
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    CFRelease(pixelBufferAttributes);
    return pixelBuffer;
    
}


void SetVTSessionProperty(VTSessionRef session,  CFStringRef key, int32_t value)
{
    CFNumberRef cfNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &value);
    OSStatus status = VTSessionSetProperty(session, key, cfNum);
    CFRelease(cfNum);
    if (status != noErr) {
        NSString *key_string = (__bridge NSString *)(key);
        AVLogError(@"VTSessionSetProperty failed to set:%@ to %d : %d", key_string, value, status);
    }
}

// Convenience function for setting a VT property.  uint32_t
void SetVTSessionProperty(VTSessionRef session, CFStringRef key, uint32_t value)
{
    int64_t value_64 = value;
    CFNumberRef cfNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &value_64);
    OSStatus status = VTSessionSetProperty(session, key, cfNum);
    CFRelease(cfNum);
    if (status != noErr) {
        NSString *key_string = (__bridge NSString *)(key);
        AVLogError(@"VTSessionSetProperty failed to set:%@ to %d : %d", key_string, (int)value, (int)status);
    }
}

// Convenience function for setting a VT property.  bool
void SetVTSessionProperty(VTSessionRef session, CFStringRef key, bool value)
{
    CFBooleanRef cf_bool = (value) ? kCFBooleanTrue : kCFBooleanFalse;
    OSStatus status = VTSessionSetProperty(session, key, cf_bool);
    if (status != noErr) {
        NSString *key_string = (__bridge NSString *)(key);
        AVLogError(@"VTSessionSetProperty failed to set:%@ to %d : %d", key_string, (int)value, (int)status);
    }
}

// Convenience function for setting a VT property.  CFStringRef
void SetVTSessionProperty(VTSessionRef session,  CFStringRef key, CFStringRef value)
{
    OSStatus status = VTSessionSetProperty(session, key, value);
    if (status != noErr) {
        NSString *key_string = (__bridge NSString *)(key);
        NSString *value_string = (__bridge NSString *)(key);
        AVLogError(@"VTSessionSetProperty failed to set:%@ to %@ : %d", key_string, value_string, (int)status);
    }
}

// This is the callback function that VideoToolbox calls when encode is complete.
static void encodeOutputCallback(void *encoder, void *params, OSStatus status, VTEncodeInfoFlags infoFlags,
                          CMSampleBufferRef sampleBuffer )
{
    H264VideoToolboxEncoder *encoderSession = (__bridge H264VideoToolboxEncoder*)encoder;
    [encoderSession encoded:sampleBuffer status:status flags:infoFlags];
}


@interface H264VideoToolboxEncoder()
{
    VTCompressionSessionRef _encodeSession;
}

@end
@interface H264VideoToolboxEncoder (Protected)
- (BOOL)initEncoder;
- (void)finiEncoder;
- (int)realEncode:(NativeVideoFrame *)avFrame TimeStamp:(long)ts;
@end

@implementation H264VideoToolboxEncoder

- (instancetype)init
{
    self = [super init];
    if (self) {
        
    }
    return self;
}
- (int)realEncode:(NativeVideoFrame *)raw TimeStamp:(long)ts
{
    if (!_encodeSession || !&encodeOutputCallback) {
        return -1;
    }
    if (!([UIApplication sharedApplication].applicationState == UIApplicationStateActive)) {
        // Ignore all encode requests when app isn't active. In this state, the
        // hardware encoder has been invalidated by the OS.
        return -1;
    }
    
    // Get a pixel buffer from the pool and copy frame data over.
    CVPixelBufferPoolRef pixel_buffer_pool = VTCompressionSessionGetPixelBufferPool(_encodeSession);

    if (!pixel_buffer_pool) {
        [self finiEncoder];
        [self initEncoder];
        pixel_buffer_pool = VTCompressionSessionGetPixelBufferPool(_encodeSession);
        AVLogWarn(@"Resetting compression session due to invalid pool.");
    }
    
    CVPixelBufferRef pixel_buffer = static_cast<CVPixelBufferRef>(raw->native_handle());
    if (pixel_buffer) {
        // This pixel buffer might have a higher resolution than what the
        // compression session is configured to. The compression session can handle
        // that and will output encoded frames in the configured resolution
        // regardless of the input pixel buffer resolution.
        CVBufferRetain(pixel_buffer);
        pixel_buffer_pool = nullptr;
    } else {
        pixel_buffer = createCVPixelBuffer(raw);
    }

    CMTime presentation_time_stamp = CMTimeMake(ts, 1000);
    CFDictionaryRef frame_properties = NULL;

    VTEncodeInfoFlags flags;
    OSStatus status = VTCompressionSessionEncodeFrame(_encodeSession, pixel_buffer, presentation_time_stamp, kCMTimeInvalid, frame_properties, NULL, &flags);
    if (frame_properties) {
        CFRelease(frame_properties);
    }
    if (pixel_buffer) {
        CVBufferRelease(pixel_buffer);
    }
    if (status != noErr) {
        AVLogError(@"Failed to encode frame with code: %d", (int)status);
        return -1;
    }
    return 0;
}

- (BOOL)initEncoder
{
    OSStatus status= -1;
    const size_t attributes_size = 3;
    CFTypeRef keys[attributes_size] = {
        kCVPixelBufferOpenGLESCompatibilityKey,
        kCVPixelBufferIOSurfacePropertiesKey,
        kCVPixelBufferPixelFormatTypeKey
    };
    CFDictionaryRef io_surface_value = CreateCFDictionary(nil,nil,0);
    
    int64_t nv12type = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    
    CFNumberRef pixel_format = CFNumberCreate(nil, kCFNumberLongType, &nv12type);
    
    CFTypeRef values[attributes_size] = {kCFBooleanTrue, io_surface_value, pixel_format};
    
    CFDictionaryRef source_attributes = CreateCFDictionary(keys,values,attributes_size);
    
    if (io_surface_value) {
        CFRelease(io_surface_value);
        io_surface_value = nil;
    }
    if (pixel_format) {
        CFRelease(pixel_format);
        pixel_format = nil;
    }

    status = VTCompressionSessionCreate(kCFAllocatorDefault,
                                        _usingParam->width,
                                        _usingParam->height,
                                        kCMVideoCodecType_H264,
                                        NULL,
                                        source_attributes,
                                        kCFAllocatorDefault,
                                        encodeOutputCallback,
                                        (__bridge void *)self,
                                        &(_encodeSession));
    if (source_attributes) {
        CFRelease(source_attributes);
        source_attributes = nil;
    }

    if (status != noErr) {
        AVLogError(@"VTCompressionSessionCreate failed. ret = %d", (int)status);
        return -1;
    }
    
    [self configureCompressionSession:_usingParam];
    VTCompressionSessionPrepareToEncodeFrames(_encodeSession);

    return status;
}

- (void)configureCompressionSession:(struct VideoCapability *)param
{
    if (_encodeSession) {
        SetVTSessionProperty(_encodeSession,
                             kVTCompressionPropertyKey_RealTime,
                             true);// 设置实时编码输出，降低编码延迟
        
        // h264 profile, 直播一般使用baseline，可减少由于b帧带来的延时
        SetVTSessionProperty(_encodeSession,
                             kVTCompressionPropertyKey_ProfileLevel,
                             kVTProfileLevel_H264_Baseline_AutoLevel);//kVTProfileLevel_H264_Baseline_4_1
       
        SetVTSessionProperty(_encodeSession,
                             kVTCompressionPropertyKey_AllowFrameReordering,
                             false);
        int realBitrate = [Utils calcBiteRate:_usingParam->width heght:_usingParam->height fps:_usingParam->fps];
        //realBitrate = realBitrate>>10;
        [self SetEncoderBitrateBps:realBitrate];
        // 设置关键帧间隔，即gop size
        SetVTSessionProperty(_encodeSession,
                             kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             param->fps * 3);// param->fps * 2  param->fps * 3
        SetVTSessionProperty(_encodeSession,
                             kVTCompressionPropertyKey_ExpectedFrameRate,
                             param->fps);
    }
}

- (void)SetEncoderBitrateBps:(uint32_t)bps
{
    if (_encodeSession) {
    // 设置编码码率(比特率)，如果不设置，默认将会以很低的码率编码，导致编码出来的视频很模糊
      SetVTSessionProperty(_encodeSession, kVTCompressionPropertyKey_AverageBitRate, bps);
        
        // TODO(tkchin): Add a helper method to set array value.
        int64_t data_limit_bytes_per_second_value = (int64_t)(bps * kLimitToAverageBitRateFactor / 8);
        CFNumberRef bytes_per_second = CFNumberCreate(kCFAllocatorDefault,
                                                      kCFNumberSInt64Type,
                                                      &data_limit_bytes_per_second_value);
        int64_t one_second_value = 1;
        CFNumberRef one_second = CFNumberCreate(kCFAllocatorDefault,
                                                kCFNumberSInt64Type,
                                                &one_second_value);
        const void* nums[2] = {bytes_per_second, one_second};
        CFArrayRef data_rate_limits = CFArrayCreate(NULL, nums, 2, &kCFTypeArrayCallBacks);
        OSStatus status = VTSessionSetProperty(_encodeSession,
                                               kVTCompressionPropertyKey_DataRateLimits,
                                               data_rate_limits);
        if (bytes_per_second) {
            CFRelease(bytes_per_second);
        }
        if (one_second) {
            CFRelease(one_second);
        }
        if (data_rate_limits) {
            CFRelease(data_rate_limits);
        }
        if (status != noErr) {
            AVLogError(@"Failed to set data rate limit: %d", (int)status);
        }
    }
}

- (void)finiEncoder
{
    if (_encodeSession) {
        VTCompressionSessionInvalidate(_encodeSession);
        CFRelease(_encodeSession);
        _encodeSession = nil;
    }
}

-(void)encoded:(CMSampleBufferRef)sampleBuffer status:(OSStatus)status flags:(VTEncodeInfoFlags)infoFlags
{
    if (status != noErr) {
        AVLogError(@"H264 encode failed.");
        return;
    }
    
    
    // Convert the sample buffer into a buffer suitable for RTP packetization.
    // TODO(tkchin): Allocate buffers through a pool.
    
    if (!CMSampleBufferDataIsReady(sampleBuffer))
    {
        AVLogWarn(@"encodeOutputCallback data is not ready status:%d infoFlags:%d", status, infoFlags);
        return;
    }
    int result=0;
    unsigned char* pTmp = _pTmpOut;
    // Check if we have got a key frame first
    CFDictionaryRef theDic = (CFDictionaryRef)CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0);
    BOOL keyframe = !CFDictionaryContainsKey(theDic, kCMSampleAttachmentKey_NotSync);
    
    if (keyframe) {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        
        if (statusCode == noErr)
        {
            pTmp = _pTmpCfg;
            uint8_t* pData = (uint8_t *)sparameterSet;
            
            pTmp[0] = 0x17;
            pTmp[1] = 0x00;
            pTmp[2] = 0x00;
            pTmp[3] = 0x00;
            pTmp[4] = 0x00;
            
            pTmp[5] =0x01;
            pTmp[6] =pData[1];
            pTmp[7] =pData[2];
            pTmp[8] =pData[3];
            pTmp[9] =0xff;
            pTmp[10]=0xe1;
            
            short length = ntohs(sparameterSetSize);
            memcpy(pTmp + 11, &length, 2);
            memcpy(pTmp + 13, pData, sparameterSetSize);
            
            result = 13 + (int)sparameterSetSize;
            pTmp += result;
            // Found sps and now check for pps
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            if (statusCode == noErr)
            {
                pTmp[0] = 0x1;
                short length = ntohs(pparameterSetSize);
                memcpy(pTmp + 1, &length, 2);
                
                memcpy(pTmp + 3, pparameterSet, pparameterSetSize);
                
                result += pparameterSetSize +3;
                _cfgLen = result;
                
                pTmp = _pTmpOut;
                pTmp[0] = 0x17;
                pTmp[1] = 0x01;
                pTmp[2] = 0x00;
                pTmp[3] = 0x00;
                pTmp[4] = 0x00;
                pTmp += 5;
                result = 5;
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4;
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            
            // Read the NAL unit length
            uint32_t ipayload = 0;
            memcpy(&ipayload, dataPointer + bufferOffset, AVCCHeaderLength);
            
            // Convert the length value from Big-endian to Little-endian
            ipayload = CFSwapInt32BigToHost(ipayload);
            int len = ntohl(ipayload);
            int type = dataPointer[bufferOffset + AVCCHeaderLength]&0x1f;
            if (type != 6)
            {
                if (type == 5)
                {
                    memcpy(pTmp, &len, 4);
                    memcpy(pTmp + 4, dataPointer + bufferOffset + AVCCHeaderLength, ipayload);
                    pTmp += ipayload + 4;
                    result += ipayload + 4;
                }
                else
                {
                    if (result == 0)
                    {
                        pTmp = _pTmpOut;
                        pTmp[0] = 0x27;
                        pTmp[1] = 0x01;
                        pTmp[2] = 0x00;
                        pTmp[3] = 0x00;
                        pTmp[4] = 0x00;
                        pTmp += 5;
                        result = 5;
                    }
                    
                    memcpy(pTmp, &len, 4);
                    memcpy(pTmp+4, dataPointer + bufferOffset + AVCCHeaderLength, ipayload);
                    
                    pTmp += ipayload+4;
                    result += ipayload+4;
                }
            }
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + ipayload;
        }
        @autoreleasepool
        {
            if(keyframe && _cfgLen > 0)
            {
                
                if (_delegate)
                {
                    [_delegate encoded:_pTmpCfg length:_cfgLen timestamp:0];
                    [_delegate encoded:_pTmpOut length:result timestamp:0];
                }
            }
            else if(!keyframe)
            {
                if (_delegate)
                {
                    [_delegate encoded:_pTmpOut length:result timestamp:0];
                }
            }
        }
    }
}
@end
