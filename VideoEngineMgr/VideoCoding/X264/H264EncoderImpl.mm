//
//  H264EncoderImpl.m
//  AVSession
//
//  Created by whw on 2016/11/22.
//  Copyright © 2016年 meixin. All rights reserved.
//

#import "H264EncoderImpl.h"
#import "x264.h"
#import "libavformat/avformat.h"
#import "Utils.h"
#import "libyuv.h"
#include "VideoDefines.h"
#include "VideoFrame.h"
typedef struct
{
    x264_param_t * param;
    x264_t *handle;
    x264_picture_t * picture;
    x264_nal_t  *nal;
} Encoder;

@interface H264EncoderImpl ()
{
    Encoder*        _encoder;
}

@end
@interface H264EncoderImpl (Protected)
- (BOOL)initEncoder;
- (void)finiEncoder;
- (int)realEncode:(NativeVideoFrame *)avFrame TimeStamp:(long)ts;
@end

@implementation H264EncoderImpl

- (instancetype)init
{
    self = [super init];
    if (self) {
        
    }
    return self;
}
- (int)realEncode:(NativeVideoFrame *)raw TimeStamp:(long)ts
{
    raw->native2i420();
    int framesize = raw->width()*raw->height();
    _encoder->picture->img.i_stride[kYPlane] = raw->stride(kYPlane);
    _encoder->picture->img.i_stride[kUPlane] = raw->stride(kUPlane);
    _encoder->picture->img.i_stride[kVPlane] = raw->stride(kVPlane);
    _encoder->picture->img.i_stride[kNumOfPlanes] = 0;
    memcpy(_encoder->picture->img.plane[kYPlane],raw->buffer(kYPlane), framesize);
    memcpy(_encoder->picture->img.plane[kUPlane],raw->buffer(kUPlane), framesize>>2);
    memcpy(_encoder->picture->img.plane[kVPlane],raw->buffer(kVPlane), framesize>>2);
    _encoder->picture->img.plane[kNumOfPlanes] = 0;
    _encoder->picture->img.i_csp = X264_CSP_I420;
    return [self CompressBuffer:_encoder TS:ts];
}
- (BOOL)initEncoder
{
    Encoder *en = (Encoder *) malloc(sizeof(Encoder));
    en->param = (x264_param_t *) malloc(sizeof(x264_param_t));
    en->picture = (x264_picture_t *) malloc(sizeof(x264_picture_t));
    
    x264_param_default_preset(en->param, "superfast" , "zerolatency");
    
    en->param->b_sliced_threads = 0;
    en->param->i_threads = 1;
    en->param->rc.i_rc_method = X264_RC_ABR;
    
    int realBitrate = [Utils calcBiteRate:_usingParam->width heght:_usingParam->height fps:_usingParam->fps];
    realBitrate = realBitrate>>10;
    en->param->rc.i_vbv_max_bitrate= 2 * realBitrate;
    en->param->rc.i_bitrate = realBitrate;
    en->param->rc.i_vbv_buffer_size = 2 * realBitrate;
    
    en->param->i_fps_num = _usingParam->fps;
    en->param->i_fps_den = 1;
    en->param->i_keyint_min = _usingParam->fps * 2;
    en->param->i_keyint_max = _usingParam->fps * 2;
    
    en->param->i_timebase_num        = 1;
    en->param->i_timebase_den        = 1000;
    
    x264_param_apply_profile(en->param,"baseline");
    
    en->param->i_csp = X264_CSP_I420;
    en->param->i_log_level = X264_LOG_NONE;
    en->param->i_width = _usingParam->width; //set frame width
    en->param->i_height = _usingParam->height; //set frame height

    if ((en->handle = x264_encoder_open(en->param)) == 0) {
        //tyy
        free(en->param);
        free(en->picture);
        free(en);
        return NO;
    }
    /* Create a new pic */
    x264_picture_alloc(en->picture, X264_CSP_I420, en->param->i_width, en->param->i_height);
    
    _encoder = en;
    return YES;
}
- (void)finiEncoder
{
    if(!_encoder)
        return;
    
    if(_encoder->picture)
    {
        x264_picture_clean(_encoder->picture);
        free(_encoder->picture);
        _encoder->picture	= 0;
    }
    if(_encoder->param)
    {
        free(_encoder->param);
        _encoder->param=0;
    }
    if(_encoder->handle)
    {
        x264_encoder_close(_encoder->handle);
    }
    free(_encoder);
    
    _cfgLen = 0;
}

- (int)CompressBuffer:(Encoder *)en TS:(long)ts
{
    x264_picture_t pic_out;
    
    int nNal=-1;
    int result=0;
    int i=0;
    
    en->picture->i_type = 0;
    en->picture->i_pts = ts;
    //LOGI("******************before encode");
    int ret = x264_encoder_encode( en->handle, &(en->nal), &nNal, en->picture ,&pic_out);
    if( ret < 0 )
    {
        AVLogWarn(@"******************encode failed");
        return -1;
    }
    
    if(!nNal)
    {
        return 0;
    }
    
    if(!_pTmpOut || !_pTmpCfg)
        return -1;
    
    unsigned char* pTmp = _pTmpOut;
    for (i = 0; i < nNal; i++)
    {
        if(en->nal[i].i_type == 6)
            continue;
        
        if(pic_out.b_keyframe)
        {
            if(en->nal[i].i_type == 5 )
            {
                int32_t length = ntohl(en->nal[i].i_payload - 3);
                memcpy(pTmp, &length, 4);
                memcpy(pTmp + 4, en->nal[i].p_payload + 3, en->nal[i].i_payload - 3);
                pTmp += en->nal[i].i_payload + 1;
                result += en->nal[i].i_payload + 1;
            }
            else if(en->nal[i].i_type == 7)
            {
                // SPS
                pTmp = _pTmpCfg;
                uint8_t* pData = en->nal[i].p_payload + 4;
                
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
                
                short length = ntohs(en->nal[i].i_payload - 4);
                memcpy(pTmp + 11, &length, 2);
                memcpy(pTmp + 13, pData, en->nal[i].i_payload - 4);
                
                result = 9 + en->nal[i].i_payload;
                pTmp += result;
            }
            else if(en->nal[i].i_type == 8)
            {
                // PPS
                pTmp[0] = 0x1;
                short length = ntohs(en->nal[i].i_payload - 4);
                memcpy(pTmp + 1, &length, 2);
                memcpy(pTmp + 3, en->nal[i].p_payload + 4, en->nal[i].i_payload - 4);
                
                result += en->nal[i].i_payload - 1;
                _cfgLen = result;
                
                // key frame
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
        else
        {
            // p frame
            if(result == 0)
            {
                pTmp = _pTmpOut;
                pTmp[0] = 0x27;
                pTmp[1] = 0x01;
                pTmp[2] = 0x00;
                pTmp[3] = 0x00;
                pTmp[4] = 0x00;
                pTmp += 5;
                result = 5;
                
                memcpy(pTmp, en->nal[i].p_payload, en->nal[i].i_payload);
                int32_t length = ntohl(en->nal[i].i_payload - 4);
                memcpy(pTmp, &length, 4);
                
                pTmp += en->nal[i].i_payload;
                result += en->nal[i].i_payload;
            }
            else
            {
                int32_t length = ntohl(en->nal[i].i_payload - 3);
                memcpy(pTmp, &length, 4);
                memcpy(pTmp + 4, en->nal[i].p_payload + 3, en->nal[i].i_payload - 3);
                pTmp += en->nal[i].i_payload + 1;
                result += en->nal[i].i_payload + 1;
            }
        }
    }
    
    if (!result)
    {
        return 0;
    }
    
    unsigned int outts = (unsigned int)(pic_out.i_dts != 0 ? pic_out.i_dts : ts);
    
    @autoreleasepool
    {
        if(pic_out.b_keyframe && _cfgLen > 0)
        {
            
            if (_delegate)
            {
                [_delegate encoded:_pTmpCfg length:_cfgLen timestamp:outts];
                [_delegate encoded:_pTmpOut length:result timestamp:outts];
            }
        }
        else if(!pic_out.b_keyframe)
        {
            if (_delegate)
            {
                [_delegate encoded:_pTmpOut length:result timestamp:outts];
            }
        }
    }
    return result;
}


@end
