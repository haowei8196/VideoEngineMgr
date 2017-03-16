//
//  VideoFrame.cpp
//  AVSession
//
//  Created by whw on 2016/12/21.
//  Copyright © 2016年 meixin. All rights reserved.
//

#include "VideoFrame.h"
#include <string>
#include <stdlib.h>
#include <assert.h>
#include "libyuv.h"
#include <CoreVideo/CoreVideo.h>
Plane::Plane()
: allocated_size_(0),
plane_size_(0),buffer_(0),
stride_(0) {}

Plane::~Plane() {
    if (buffer_)
        free(buffer_);
}


int Plane::MaybeResize(int new_size) {
    if (new_size <= 0)
        return -1;
    if (new_size <= allocated_size_)
        return 0;
    uint8_t* new_buffer = (uint8_t*)malloc(new_size);
    if (buffer_) {
        free(buffer_);
    }
    buffer_=new_buffer;
    allocated_size_ = new_size;
    plane_size_ = new_size;
    return 0;
}

int Plane::Copy(int size, int stride, const uint8_t* buffer) {
    if (MaybeResize(size) < 0)
        return -1;
    memcpy(buffer_, buffer, size);
    plane_size_ = size;
    stride_ = stride;
    return 0;
}


I420VideoFrame::I420VideoFrame()
: width_(0),
height_(0)
{}

I420VideoFrame::~I420VideoFrame() {}

int I420VideoFrame::CreateEmptyFrame(int width,
                      int height,
                      int stride_y,
                      int stride_u,
                      int stride_v)
{
    Reset();
    int half_height = (height+1)/2;
    int size_y = stride_y*height;
    int size_u = stride_u*half_height;
    int size_v = stride_v*half_height;
    if (CheckDimensions(width, height, stride_y, stride_u, stride_v) < 0)
        return -1;
    y_plane_.MaybeResize(size_y);
    u_plane_.MaybeResize(size_u);
    v_plane_.MaybeResize(size_v);
    
    y_plane_.stride(stride_y);
    u_plane_.stride(stride_u);
    v_plane_.stride(stride_v);
    width_ = width;
    height_ = height;
    return 0;
}

int I420VideoFrame::CreateFrame(const uint8_t* buffer_y,
                                const uint8_t* buffer_u,
                                const uint8_t* buffer_v,
                                int width, int height,
                                int stride_y, int stride_u, int stride_v)
{
    Reset();
    int half_height = (height+1)/2;
    int size_y = stride_y*height;
    int size_u = stride_u*half_height;
    int size_v = stride_v*half_height;
    if (CheckDimensions(width, height, stride_y, stride_u, stride_v) < 0)
        return -1;
    y_plane_.Copy(size_y, stride_y, buffer_y);
    u_plane_.Copy(size_u, stride_u, buffer_u);
    v_plane_.Copy(size_v, stride_v, buffer_v);
    width_ = width;
    height_ = height;
    return 0;
}


uint8_t* I420VideoFrame::buffer(PlaneType type) {
    Plane* plane_ptr = GetPlane(type);
    if (plane_ptr)
        return plane_ptr->buffer();
    return NULL;
}

const uint8_t* I420VideoFrame::buffer(PlaneType type) const {
    const Plane* plane_ptr = GetPlane(type);
    if (plane_ptr)
        return plane_ptr->buffer();
    return NULL;
}

int I420VideoFrame::stride(PlaneType type) const {
    const Plane* plane_ptr = GetPlane(type);
    if (plane_ptr)
        return plane_ptr->stride();
    return -1;
}

void I420VideoFrame::Reset() {
    y_plane_.ResetSize();
    u_plane_.ResetSize();
    v_plane_.ResetSize();
}


int I420VideoFrame::CheckDimensions(int width, int height,
                                    int stride_y, int stride_u, int stride_v) {
    int half_width = (width + 1) / 2;
    if (width < 1 || height < 1 ||
        stride_y < width || stride_u < half_width || stride_v < half_width)
        return -1;
    return 0;
}

const Plane* I420VideoFrame::GetPlane(PlaneType type) const {
    switch (type) {
        case kYPlane :
            return &y_plane_;
        case kUPlane :
            return &u_plane_;
        case kVPlane :
            return &v_plane_;
        default:
            assert(false);
    }
    return NULL;
}

Plane* I420VideoFrame::GetPlane(PlaneType type) {
    switch (type) {
        case kYPlane :
            return &y_plane_;
        case kUPlane :
            return &u_plane_;
        case kVPlane :
            return &v_plane_;
        default:
            assert(false);
    }
    return NULL;
}
using namespace libyuv;
NativeVideoFrame::NativeVideoFrame():I420VideoFrame(),native_frame_(0)
{
    
}
int NativeVideoFrame::CreateFrame(void* nativeframe)
{
    Reset();
    
    CVPixelBufferRef imageBuffer = (CVPixelBufferRef)nativeframe;
    
    width_ = (int)CVPixelBufferGetWidth(imageBuffer);
    height_ = (int)CVPixelBufferGetHeight(imageBuffer);
    

    native_frame_ = (void*)(imageBuffer);

    return 0;
}
int NativeVideoFrame::native2i420()
{
    if (native_frame_)
    {
        CVPixelBufferRef imageBuffer = (CVPixelBufferRef)native_frame_;
        CVPixelBufferLockBaseAddress(imageBuffer, 0);

        int stride_y = width_;
        int stride_uv = (width_ + 1) / 2;
        
        int half_height = (height_+1)/2;
        int size_y = stride_y*height_;
        int size_u = stride_uv*half_height;
        int size_v = stride_uv*half_height;
        if (CheckDimensions(width_, height_, stride_y, stride_uv, stride_uv) < 0)
            return -1;
        y_plane_.MaybeResize(size_y);
        u_plane_.MaybeResize(size_u);
        v_plane_.MaybeResize(size_v);
        
        y_plane_.stride(stride_y);
        u_plane_.stride(stride_uv);
        v_plane_.stride(stride_uv);
        
        const int kYPlaneIndex = 0;
        const int kUVPlaneIndex = 1;
        
        uint8_t *yPlaneAddress = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer,kYPlaneIndex);
        size_t ystride = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,kYPlaneIndex);
        
        uint8_t *uvPlaneAddress = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer,kUVPlaneIndex);
        size_t uvstride = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,kUVPlaneIndex);
        
        NV12ToI420(yPlaneAddress,  (int)ystride,
                         uvPlaneAddress, (int)uvstride,
                         buffer(kYPlane),
                         stride(kYPlane),
                         buffer(kUPlane),
                         stride(kUPlane),
                         buffer(kVPlane),
                         stride(kVPlane),
                         width_, height_);
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    }
    return 0;
}
void* NativeVideoFrame::native_handle()
{
    /*if (!native_frame_)
    {
        CFDictionaryRef pixelBufferAttributes = CFDictionaryCreate(kCFAllocatorDefault, nil, nil, 0,
                                                                   &kCFTypeDictionaryKeyCallBacks,
                                                                   &kCFTypeDictionaryValueCallBacks);
        
        CVPixelBufferRef pixelBuffer;
        CVPixelBufferCreate(NULL, width_, height_, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, pixelBufferAttributes, &pixelBuffer);
        
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        
        
        uint8_t* dst_y = reinterpret_cast<uint8_t*>(
                                                    CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0));
        int dst_stride_y = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        uint8_t* dst_uv = reinterpret_cast<uint8_t*>(
                                                     CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1));
        int dst_stride_uv = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
        // Convert I420 to NV12.
        I420ToNV12(buffer(kYPlane),stride(kYPlane),
                           buffer(kUPlane),stride(kUPlane),
                           buffer(kVPlane),stride(kVPlane),
                           dst_y, dst_stride_y, dst_uv, dst_stride_uv,
                           width_, height_);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        CFRelease(pixelBufferAttributes);
        native_frame_ = (void*)pixelBuffer;
    }*/
    return native_frame_;
}
void NativeVideoFrame::Reset()
{
    I420VideoFrame::Reset();
    /*if (native_frame_)
        CVBufferRelease((CVPixelBufferRef)native_frame_);*/
    native_frame_ = 0;
}
