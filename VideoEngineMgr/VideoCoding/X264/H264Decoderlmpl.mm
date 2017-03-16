//
//  H264Decoderlmpl.m
//  AVSession
//
//  Created by whw on 2016/11/22.
//  Copyright © 2016年 meixin. All rights reserved.
//

#import "H264Decoderlmpl.h"
#ifdef __cplusplus
extern "C"
{
#endif
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/pixdesc.h"
#include "libavformat/avformat.h"
#ifdef __cplusplus
}
#endif

#import "Utils.h"
//#import "AVDefine.h"
#include "VideoFrame.h"
/**
 * Sequence parameter set
 */
typedef struct SPS {
    unsigned int sps_id;
    int profile_idc;
    int level_idc;
    int chroma_format_idc;
    int transform_bypass;              ///< qpprime_y_zero_transform_bypass_flag
    int log2_max_frame_num;            ///< log2_max_frame_num_minus4 + 4
    int poc_type;                      ///< pic_order_cnt_type
    int log2_max_poc_lsb;              ///< log2_max_pic_order_cnt_lsb_minus4
    int delta_pic_order_always_zero_flag;
    int offset_for_non_ref_pic;
    int offset_for_top_to_bottom_field;
    int poc_cycle_length;              ///< num_ref_frames_in_pic_order_cnt_cycle
    int ref_frame_count;               ///< num_ref_frames
    int gaps_in_frame_num_allowed_flag;
    int mb_width;                      ///< pic_width_in_mbs_minus1 + 1
    int mb_height;                     ///< pic_height_in_map_units_minus1 + 1
    int frame_mbs_only_flag;
    int mb_aff;                        ///< mb_adaptive_frame_field_flag
    int direct_8x8_inference_flag;
    int crop;                          ///< frame_cropping_flag
    
    /* those 4 are already in luma samples */
    unsigned int crop_left;            ///< frame_cropping_rect_left_offset
    unsigned int crop_right;           ///< frame_cropping_rect_right_offset
    unsigned int crop_top;             ///< frame_cropping_rect_top_offset
    unsigned int crop_bottom;          ///< frame_cropping_rect_bottom_offset
    int vui_parameters_present_flag;
    AVRational sar;
    int video_signal_type_present_flag;
    int full_range;
    int colour_description_present_flag;
    enum AVColorPrimaries color_primaries;
    enum AVColorTransferCharacteristic color_trc;
    enum AVColorSpace colorspace;
    int timing_info_present_flag;
    uint32_t num_units_in_tick;
    uint32_t time_scale;
    int fixed_frame_rate_flag;
    short offset_for_ref_frame[256]; // FIXME dyn aloc?
    int bitstream_restriction_flag;
    int num_reorder_frames;
    int scaling_matrix_present;
    uint8_t scaling_matrix4[6][16];
    uint8_t scaling_matrix8[6][64];
    int nal_hrd_parameters_present_flag;
    int vcl_hrd_parameters_present_flag;
    int pic_struct_present_flag;
    int time_offset_length;
    int cpb_cnt;                          ///< See H.264 E.1.2
    int initial_cpb_removal_delay_length; ///< initial_cpb_removal_delay_length_minus1 + 1
    int cpb_removal_delay_length;         ///< cpb_removal_delay_length_minus1 + 1
    int dpb_output_delay_length;          ///< dpb_output_delay_length_minus1 + 1
    int bit_depth_luma;                   ///< bit_depth_luma_minus8 + 8
    int bit_depth_chroma;                 ///< bit_depth_chroma_minus8 + 8
    int residual_color_transform_flag;    ///< residual_colour_transform_flag
    int constraint_set_flags;             ///< constraint_set[0-3]_flag
    int new_;                              ///< flag to keep track if the decoder context needs re-init due to changed SPS
} SPS;


@interface H264Decoderlmpl ()
{
    AVCodecContext      *_videoCodecCtx;
    AVPacket            _VideoPkt;
    struct SwsContext   *_pSwsCxt;
    AVFrame *_videoFrame;
}
@end


@interface H264Decoderlmpl (Protected)
- (BOOL)checkDecoder;
- (BOOL)initDecoder;
- (void)finiDecoder;
- (void)realDecode:(uint8_t *)data length:(uint32_t)len TS:(unsigned int)ts;
@end


@implementation H264Decoderlmpl

#define MAKEFOURCC(ch0, ch1, ch2, ch3)              \
((uint32_t)(Byte)(ch0) | ((uint32_t)(Byte)(ch1) << 8) |   \
((uint32_t)(Byte)(ch2) << 16) | ((uint32_t)(Byte)(ch3) << 24 ))

- (instancetype)init
{
    self = [super init];
    if (self) {
        _width = 0;
        _height = 0;
    }
    return self;
}

#pragma mark - video decode
- (BOOL)initDecoder
{
    av_register_all();
    AVCodec * iCodec=avcodec_find_decoder(AV_CODEC_ID_H264);
    if (!iCodec) {
        return false;
    }
    _videoCodecCtx = avcodec_alloc_context3(iCodec);
    _videoCodecCtx->time_base.num = 1;
    _videoCodecCtx->time_base.den = 25;
    _videoCodecCtx->pix_fmt = AV_PIX_FMT_YUV420P;
    _videoCodecCtx->frame_number = 1;
    _videoCodecCtx->codec_type = AVMEDIA_TYPE_VIDEO;
    _videoCodecCtx->width = _width;
    _videoCodecCtx->height = _height;
    if ((iCodec->capabilities & CODEC_CAP_TRUNCATED)>0) {
        _videoCodecCtx->flags|=CODEC_FLAG_TRUNCATED;
    }
    
    if (avcodec_open2(_videoCodecCtx, iCodec,NULL)<0) {
        return false;
    }
    
    _videoFrame = av_frame_alloc();
    if (!_videoFrame) {
        avcodec_close(_videoCodecCtx);
        return false;
    }
    
    return true;
}
- (void)finiDecoder
{
    if (_videoFrame)
    {
        av_frame_free(&_videoFrame);
        _videoFrame = NULL;
    }
    
    if (_videoCodecCtx) {
        
        avcodec_close(_videoCodecCtx);
        _videoCodecCtx = NULL;
    }
    sws_freeContext(_pSwsCxt);
    _pSwsCxt = NULL;
}
- (BOOL)checkDecoder
{
    int width = 0,height = 0;
    [self AnalyzeSPSHeader:_spsppsBuf + 4 length:_spslen RetWidth:&width RetHeight:&height];
    if(width != _width || height != _height)
    {
        AVLogInfo(@"w = %d h = %d", width, height);
        
        [self finiDecoder];
        
        _width = width;
        _height = height;
        
        if(![self initDecoder])
            return FALSE;
    }
    else
    {
        return FALSE;
    }
    [self decodeData:_spsppsBuf Length:_spslen+_ppslen+8];
    return TRUE;
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
        
        curpos[0] = 0x00;
        curpos[1] = 0x00;
        curpos[2] = 0x00;
        curpos[3] = 0x01;
        
        curIdx += 4 + newDataLen; 
    } while (curIdx < reallen);
    
    if (curIdx != reallen)
    {
        AVLogWarn(@"Bad video len = %d, header = %02x, %02x", len, data[0], data[1]);
        return;
    }
    
    Boolean nRet = [self decodeData:realpos Length:reallen];
    
    if(nRet)
    {
        _i420Frame->CreateFrame(_videoFrame->data[kYPlane],
         _videoFrame->data[kUPlane],
         _videoFrame->data[kVPlane],
         _videoFrame->width, _videoFrame->height,
         _videoFrame->linesize[kYPlane],
         _videoFrame->linesize[kUPlane],
         _videoFrame->linesize[kVPlane]);
        if (_delegate) {
            [_delegate decoded:_i420Frame];
        }
    }
    else
    {
        // err
        AVLogError(@"decode err");
    }
}

- (Boolean)decodeData:(Byte*)Data Length:(int)Len
{
    //NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    
    int iPrt=0;
    av_init_packet(&_VideoPkt);
    _VideoPkt.data = Data;////(uint8_t *)Data.bytes;
    _VideoPkt.size = Len;
    Boolean ret;
    ret= (avcodec_decode_video2(_videoCodecCtx, _videoFrame, &iPrt, &_VideoPkt) >= 0);
    av_free_packet(&_VideoPkt);
    
    if  (!ret)
        return false;
    
    //NSLog(@"decode len = %d dur = %f", Len, [NSDate timeIntervalSinceReferenceDate] - start);
    
    return true;
}

- (void) AnalyzeSPSHeader:(uint8_t *)data
                   length:(uint32_t)len
                 RetWidth:(int32_t*)width
                RetHeight:(int32_t*)height
{
    SPS *sps = (SPS *)av_mallocz(sizeof(SPS));
    memset(sps, 0, sizeof(SPS));
    if(0 == [self GetSPS:data Length:len SPS:sps])
    {
        *width  = 16 * sps->mb_width;
        *height = 16 * sps->mb_height;
    }
    
    av_free(sps);
}

- (int) GetSPS:(uint8_t *)data
        Length:(uint32_t)len
           SPS:(SPS*)sps
{
    int profile_idc, level_idc, constraint_set_flags = 0;
    unsigned int sps_id;
    int i, log2_max_frame_num_minus4;
    
#define get_bits1(x) [self getUValue:data Length:len Count:1 Start:&start]
#define get_bits(x, y) [self getUValue:data Length:len Count:y Start:&start]
#define skip_bits(x, y) start += y
#define get_ue_golomb(x) [self getUeValue:data Length:len Start:&start]
#define get_ue_golomb_31(x) get_ue_golomb(x)
#define get_se_golomb(x) get_ue_golomb(x)
#define MAX_SPS_COUNT 32
    
    uint32_t start = 8;//skip 8 bit sps header
    
    profile_idc           = get_bits(&h->gb, 8);
    constraint_set_flags |= get_bits1(&h->gb) << 0;   // constraint_set0_flag
    constraint_set_flags |= get_bits1(&h->gb) << 1;   // constraint_set1_flag
    constraint_set_flags |= get_bits1(&h->gb) << 2;   // constraint_set2_flag
    constraint_set_flags |= get_bits1(&h->gb) << 3;   // constraint_set3_flag
    constraint_set_flags |= get_bits1(&h->gb) << 4;   // constraint_set4_flag
    constraint_set_flags |= get_bits1(&h->gb) << 5;   // constraint_set5_flag
    skip_bits(&h->gb, 2);                             // reserved_zero_2bits
    level_idc = get_bits(&h->gb, 8);
    sps_id    = get_ue_golomb_31(&h->gb);
    
    if (sps_id >= MAX_SPS_COUNT) {
        return AVERROR_INVALIDDATA;
    }
    
    sps->sps_id               = sps_id;
    sps->time_offset_length   = 24;
    sps->profile_idc          = profile_idc;
    sps->constraint_set_flags = constraint_set_flags;
    sps->level_idc            = level_idc;
    sps->full_range           = -1;
    
    memset(sps->scaling_matrix4, 16, sizeof(sps->scaling_matrix4));
    memset(sps->scaling_matrix8, 16, sizeof(sps->scaling_matrix8));
    sps->scaling_matrix_present = 0;
    sps->colorspace = AVCOL_SPC_UNSPECIFIED;//2; //AVCOL_SPC_UNSPECIFIED
    
    if (sps->profile_idc == 100 ||  // High profile
        sps->profile_idc == 110 ||  // High10 profile
        sps->profile_idc == 122 ||  // High422 profile
        sps->profile_idc == 244 ||  // High444 Predictive profile
        sps->profile_idc ==  44 ||  // Cavlc444 profile
        sps->profile_idc ==  83 ||  // Scalable Constrained High profile (SVC)
        sps->profile_idc ==  86 ||  // Scalable High Intra profile (SVC)
        sps->profile_idc == 118 ||  // Stereo High profile (MVC)
        sps->profile_idc == 128 ||  // Multiview High profile (MVC)
        sps->profile_idc == 138 ||  // Multiview Depth High profile (MVCD)
        sps->profile_idc == 144) {  // old High444 profile
        sps->chroma_format_idc = get_ue_golomb_31(&h->gb);
        if (sps->chroma_format_idc > 3U) {
            goto fail;
        } else if (sps->chroma_format_idc == 3) {
            sps->residual_color_transform_flag = get_bits1(&h->gb);
            if (sps->residual_color_transform_flag) {
                goto fail;
            }
        }
        sps->bit_depth_luma   = get_ue_golomb(&h->gb) + 8;
        sps->bit_depth_chroma = get_ue_golomb(&h->gb) + 8;
        if (sps->bit_depth_chroma != sps->bit_depth_luma) {
            goto fail;
        }
        if (sps->bit_depth_luma > 14U || sps->bit_depth_chroma > 14U) {
            goto fail;
        }
        sps->transform_bypass = get_bits1(&h->gb);
    } else {
        sps->chroma_format_idc = 1;
        sps->bit_depth_luma    = 8;
        sps->bit_depth_chroma  = 8;
    }
    
    log2_max_frame_num_minus4 = get_ue_golomb(&h->gb);
    if (log2_max_frame_num_minus4 > 8) {
        goto fail;
    }
    sps->log2_max_frame_num = log2_max_frame_num_minus4 + 4;
    
    sps->poc_type = get_ue_golomb_31(&h->gb);
    
    if (sps->poc_type == 0) { // FIXME #define
        unsigned t = get_ue_golomb(&h->gb);
        if (t>12) {
            goto fail;
        }
        sps->log2_max_poc_lsb = t + 4;
    } else if (sps->poc_type == 1) { // FIXME #define
        sps->delta_pic_order_always_zero_flag = get_bits1(&h->gb);
        sps->offset_for_non_ref_pic           = get_se_golomb(&h->gb);
        sps->offset_for_top_to_bottom_field   = get_se_golomb(&h->gb);
        sps->poc_cycle_length                 = get_ue_golomb(&h->gb);
        
        if ((unsigned)sps->poc_cycle_length >=
            FF_ARRAY_ELEMS(sps->offset_for_ref_frame)) {
            goto fail;
        }
        
        for (i = 0; i < sps->poc_cycle_length; i++)
            sps->offset_for_ref_frame[i] = get_se_golomb(&h->gb);
    } else if (sps->poc_type != 2) {
        goto fail;
    }
    
    sps->ref_frame_count = get_ue_golomb_31(&h->gb);
    sps->gaps_in_frame_num_allowed_flag = get_bits1(&h->gb);
    sps->mb_width                       = get_ue_golomb(&h->gb) + 1;
    sps->mb_height                      = get_ue_golomb(&h->gb) + 1;
    
    sps->frame_mbs_only_flag = get_bits1(&h->gb);
    if (!sps->frame_mbs_only_flag)
        sps->mb_aff = get_bits1(&h->gb);
    else
        sps->mb_aff = 0;
    
    sps->direct_8x8_inference_flag = get_bits1(&h->gb);
    
    sps->crop = get_bits1(&h->gb);
    sps->crop_left   =
    sps->crop_right  =
    sps->crop_top    =
    sps->crop_bottom =
    sps->crop        = 0;
    
    sps->vui_parameters_present_flag = get_bits1(&h->gb);
    
    if (!sps->sar.den)
        sps->sar.den = 1;
    
    sps->new_ = 1;
    return 0;
    
fail:
    return -1;
}
- (uint32_t)getUeValue:(uint8_t *)pBuf Length:(uint32_t)ulen Start:(uint32_t *)uStartBit
{
    //计算0bit的个数
    uint32_t nZeroNum = 0;
    uint32_t nStartBit = *uStartBit;
    while (nStartBit < ulen * 8)
    {
        if (pBuf[nStartBit / 8] & (0x80 >> (nStartBit % 8)))
        {
            break;
        }
        nZeroNum++;
        nStartBit++;
    }
    nStartBit ++;
    
    //计算结果
    uint32_t dwRet = 0;
    for (uint32_t i=0; i<nZeroNum; i++)
    {
        dwRet <<= 1;
        if (pBuf[nStartBit / 8] & (0x80 >> (nStartBit % 8)))
        {
            dwRet += 1;
        }
        nStartBit++;
    }
    
    *uStartBit = nStartBit;
    return (1 << nZeroNum) - 1 + dwRet;
}

- (uint8_t)getUValue:(uint8_t*)pBuf Length:(uint32_t)ulen Count:(uint32_t)bitCount Start:(uint32_t *)uStartBit
{
    uint8_t ret = 0;
    uint32_t nStartBit = *uStartBit;
    if(nStartBit + bitCount  >= ulen * 8 || bitCount > 8)
        return ret;
    
    uint32_t pos = nStartBit / 8;
    uint32_t gap = nStartBit - pos * 8;
    if(gap + bitCount <= 8)
    {
        ret = ((pBuf[pos]) << gap) >> (8-bitCount);
    }
    else
    {
        uint32_t first  = 8 - gap;
        uint32_t second = bitCount - first;
        
        ret = (((pBuf[pos]) << gap) >> (8-bitCount)) | ((pBuf[pos+1]) >> (8 - second));
    }
    
    *uStartBit += bitCount;
    return ret;
}

@end
