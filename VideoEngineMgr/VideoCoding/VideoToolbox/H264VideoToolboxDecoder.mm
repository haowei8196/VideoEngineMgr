//
//  H264VideoToolboxDecoder.m
//  AVSession
//
//  Created by whw on 2016/11/22.
//  Copyright © 2016年 meixin. All rights reserved.
//
#import <UIKit/UIKit.h>
#import "H264VideoToolboxDecoder.h"
#import <VideoToolbox/VideoToolbox.h>
#import "libyuv.h"
#include "VideoFrame.h"
#include "Utils.h"
using namespace libyuv;
// Convenience function for creating a dictionary.

CMVideoFormatDescriptionRef CreateVideoFormatDescription(const uint8_t* buffer,int32_t spslen,int32_t ppslen)
{
    CMVideoFormatDescriptionRef description = NULL;
    OSStatus status = noErr;
    // Parse the SPS and PPS into a CMVideoFormatDescription.
    const uint8_t* param_set_ptrs[2] = {};
    size_t param_set_sizes[2] = {};

    param_set_ptrs[0] = buffer+4;
    param_set_sizes[0] = spslen;
    
    param_set_ptrs[1] = buffer+4+spslen+4;
    param_set_sizes[1] = ppslen;
    
    status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, param_set_ptrs, param_set_sizes, 4, &description);
    if (status != noErr) {
        AVLogError(@"Failed to create video format description.");
        return NULL;
    }
    
    return description;
}

static void decodeOutputCallback( void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    
    if (status != noErr || pixelBuffer == nil) {
        AVLogError(@"Error decompresssing frame at time: %.3lld error: %d infoFlags: %u",
             presentationTimeStamp.value/presentationTimeStamp.timescale, (int)status, (uint32)infoFlags);
        return;
    }
    
    if (kVTDecodeInfo_FrameDropped & infoFlags) {
        AVLogWarn(@"video frame droped");
        return;
    }
    __weak H264VideoToolboxDecoder *decoder = (__bridge H264VideoToolboxDecoder *)decompressionOutputRefCon;
    [decoder decoded:pixelBuffer];
}

@interface H264VideoToolboxDecoder ()
{
    VTDecompressionSessionRef   _decoderSession;
    CMVideoFormatDescriptionRef _decoderFormatDescription;
}
@end

@interface H264VideoToolboxDecoder (Protected)
- (BOOL)checkDecoder;
- (BOOL)initDecoder;
- (void)finiDecoder;
- (void)realDecode:(uint8_t *)data length:(uint32_t)len TS:(unsigned int)ts;
@end


@implementation H264VideoToolboxDecoder


- (instancetype)init
{
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appEnterBackgroundNotification)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];

    }
    return self;
}

- (void)appEnterBackgroundNotification
{
     [self finiDecoder];
    AVLogInfo(@"appEnterBackgroundNotification");
}
- (BOOL)initDecoder
{
    AVLogInfo(@"initDecoder");
    static size_t const attributes_size = 3;
    CFTypeRef keys[attributes_size] = {
        kCVPixelBufferOpenGLESCompatibilityKey,
        kCVPixelBufferIOSurfacePropertiesKey,
        kCVPixelBufferPixelFormatTypeKey
    };
    CFDictionaryRef io_surface_value = CreateCFDictionary(NULL, NULL, 0);
    int64_t nv12type = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
//    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    
    
    CFNumberRef pixel_format = CFNumberCreate(NULL, kCFNumberLongType, &nv12type);
    CFTypeRef values[attributes_size] = {kCFBooleanTrue, io_surface_value, pixel_format};
    CFDictionaryRef attributes = CreateCFDictionary(keys, values, attributes_size);
    if (io_surface_value) {
        CFRelease(io_surface_value);
        io_surface_value = NULL;
    }
    if (pixel_format) {
        CFRelease(pixel_format);
        pixel_format = NULL;
    }
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decodeOutputCallback;
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
    OSStatus status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                                   _decoderFormatDescription,
                                                   NULL,
                                                   attributes,
                                                   &callBackRecord,
                                                   &(_decoderSession));
    CFRelease(attributes);
    if (status != noErr) {
//        [self finiDecoder];
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        AVLogError(@"Decompressed error: %@", error);
        AVLogError(@"VTDecompressionSession create failed erro %d...", (int)status);
        
        return false;
    }
    VTSessionSetProperty(_decoderSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(_decoderSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
    return true;
}
- (void)finiDecoder
{
    if (_decoderSession) {
        AVLogInfo(@"finiDecoder");
        VTDecompressionSessionInvalidate(_decoderSession);
        CFRelease(_decoderSession);
        _decoderSession = NULL;
    }
    if (_decoderFormatDescription) {
        CFRelease(_decoderFormatDescription);
        _decoderFormatDescription = nil;
    }
}
- (BOOL) checkDecoder
{
    BOOL res = FALSE;
    
    CMVideoFormatDescriptionRef input_format = CreateVideoFormatDescription(_spsppsBuf,_spslen ,_ppslen);
    if (input_format)
    {
        // Check if the video format has changed, and reinitialize decoder if
        // needed.
        if (!CMFormatDescriptionEqual(input_format, _decoderFormatDescription) || !_decoderSession)
        {
            [self finiDecoder];
            
            [self setDecoderFormatDescription:input_format];
            
            [self initDecoder];
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(input_format);
            _width = dimensions.width;
            _height = dimensions.height;
            res = TRUE;
        }
        CFRelease(input_format);
    }
    return res;
}
- (void)realDecode:(uint8_t *)data length:(uint32_t)len TS:(unsigned int)ts
{
    uint8_t* realpos = data;
    uint32_t reallen = len;
    
    if(data[5] == 0 && data[6] == 0 && data[7] == 0 && data[8] == 2)
    {
        //from flash
        int audLen = 0;
        memcpy(&audLen,data+5,4 );
        u_long newAudLen = ntohl( audLen );
        
        int seiLen = 0;
        memcpy(&seiLen,data+9+newAudLen,4 );
        u_long newSeiLen = ntohl( seiLen );
        
        int index = 9 + (int)newAudLen + 4 + (int)newSeiLen;
        
        realpos = data + index;
        reallen = len - index;
    }
    else
    {
        //from c++, no aud or sei
        realpos = data + 5;
        reallen = len - 5;
    }
    
    int curIdx = 0;
    do
    {
        uint8_t* curpos = realpos + curIdx;
        
        int dataLen = 0;
        memcpy(&dataLen, curpos, 4);
        u_long newDataLen = ntohl( dataLen );
        
        int32_t biglen = CFSwapInt32HostToBig((uint32_t)newDataLen);
        memcmp(curpos, &biglen, 4);
        
        curIdx += 4 + newDataLen;   
    } while (curIdx < reallen);
    
    if (curIdx != reallen)
    {
        AVLogWarn(@"Bad video len = %d, header = %02x, %02x", len, data[0], data[1]);
        return;
    }
    
    [self decodeData:realpos Length:reallen];
}

- (Boolean)decodeData:(Byte*)Data Length:(int)Len
{
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        [self finiDecoder];
//        AVLogInfo(@"UIApplicationStateBackground");
        return false;
    }
    CMBlockBufferRef block_buffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL, NULL, Len, NULL, NULL, 0,
                                                         Len, kCMBlockBufferAssureMemoryNowFlag,
                                                         &block_buffer);
    if (status != kCMBlockBufferNoErr) {
        AVLogError(@"Failed to create block buffer.");
        return false;
    }
    
    // Make sure block buffer is contiguous.
    CMBlockBufferRef contiguous_buffer = NULL;
    if (!CMBlockBufferIsRangeContiguous(block_buffer, 0, 0)) {
        status = CMBlockBufferCreateContiguous(NULL, block_buffer, NULL, NULL, 0, 0, 0, &contiguous_buffer);
        if (status != noErr) {
            AVLogError(@"Failed to flatten non-contiguous block buffer: %d",(int)status);
            CFRelease(block_buffer);
            return false;
        }
    } else {
        contiguous_buffer = block_buffer;
        block_buffer = NULL;
    }
    
    // Get a raw pointer into allocated memory.
    size_t block_buffer_size = 0;
    char* data_ptr = NULL;
    status = CMBlockBufferGetDataPointer(contiguous_buffer, 0, NULL,
                                         &block_buffer_size, &data_ptr);
    if (status != kCMBlockBufferNoErr) {
        AVLogError(@"Failed to get block buffer data pointer.");
        CFRelease(contiguous_buffer);
        return false;
    }
    
    memcpy(data_ptr, Data, Len);

    CMSampleBufferRef sample_buffer = NULL;
    CMSampleBufferCreate(NULL, contiguous_buffer, true, NULL,
                         NULL, _decoderFormatDescription, 1, 0, NULL, 0,
                         NULL, &sample_buffer);
    VTDecodeFrameFlags decode_flags = kVTDecodeFrame_EnableAsynchronousDecompression;
   
    status = VTDecompressionSessionDecodeFrame(_decoderSession, sample_buffer, decode_flags,
                                                        NULL, NULL);

    CFRelease(sample_buffer);
    if (status != noErr) {
        AVLogError(@"Failed to decode frame with code: %d" , (int)status);
        AVLogInfo(@"_decoderSession %@", _decoderSession);
        return false;
    }
    
    CFRelease(contiguous_buffer);
    return true;
}

- (void)setDecoderFormatDescription:(CMVideoFormatDescriptionRef)videoFrameDes
{
    if (_decoderFormatDescription == videoFrameDes) {
        return;
    }
    if (_decoderFormatDescription) {
        CFRelease(_decoderFormatDescription);
    }
    _decoderFormatDescription = videoFrameDes;
    if (_decoderFormatDescription) {
        CFRetain(_decoderFormatDescription);
    }
}
- (void)decoded:(CVPixelBufferRef)pixel_buffer_
{
    int dstWidth = (int)CVPixelBufferGetWidthOfPlane(pixel_buffer_, 0);
    int dstHeight = (int)CVPixelBufferGetHeightOfPlane(pixel_buffer_, 0);
    
    int strideuv = (dstWidth+1)/2;
    _i420Frame->CreateEmptyFrame(dstWidth,dstHeight,dstWidth,strideuv,strideuv);
    
    CVPixelBufferLockBaseAddress(pixel_buffer_, kCVPixelBufferLock_ReadOnly);
    const uint8_t* src_y = (const uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixel_buffer_, 0);
    int src_y_stride = (int)CVPixelBufferGetBytesPerRowOfPlane(pixel_buffer_, 0);
    const uint8_t* src_uv = (const uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixel_buffer_, 1);
    int src_uv_stride = (int)CVPixelBufferGetBytesPerRowOfPlane(pixel_buffer_, 1);
    NV12ToI420(src_y,src_y_stride,
                         src_uv,src_uv_stride,
                         _i420Frame->buffer(kYPlane),
                         _i420Frame->stride(kYPlane),
                         _i420Frame->buffer(kUPlane),
                         _i420Frame->stride(kUPlane),
                         _i420Frame->buffer(kVPlane),
                         _i420Frame->stride(kVPlane),
                         dstWidth,
                         dstHeight);
    CVPixelBufferUnlockBaseAddress(pixel_buffer_, kCVPixelBufferLock_ReadOnly);

    if (_delegate)
    {
        [_delegate decoded:_i420Frame];
    }
}
@end
