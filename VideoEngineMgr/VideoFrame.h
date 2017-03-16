//
//  VideoFrame.hpp
//  AVSession
//
//  Created by whw on 2016/12/21.
//  Copyright © 2016年 meixin. All rights reserved.
//

#ifndef VideoFrame_h
#define VideoFrame_h

#include <stdint.h>
#include "VideoDefines.h"
class Plane {
public:
    Plane();
    ~Plane();
    // Copy buffer: If current size is smaller
    // than current size, then a buffer of sufficient size will be allocated.
    // Return value: 0 on success ,-1 on error.
    int Copy(int size, int stride, const uint8_t* buffer);

    // Set actual size.
    void ResetSize() {plane_size_ = 0;}
    
    // Return true is plane size is zero, false if not.
    bool IsZeroSize() const {return plane_size_ == 0;}
    
    // Get stride value.
    int stride() const {return stride_;}
    void stride(int stride){stride_=stride;};
    
    // Return data pointer.
    const uint8_t* buffer() const {return buffer_;}
    // Overloading with non-const.
    uint8_t* buffer() {return buffer_;}
    
    int MaybeResize(int new_size);
private:
    // Resize when needed: If current allocated size is less than new_size, buffer
    // will be updated. Old data will be copied to new buffer.
    // Return value: 0 on success ,-1 on error.
    
    uint8_t* buffer_;
    int allocated_size_;
    int plane_size_;
    int stride_;
};


class I420VideoFrame {
public:
    I420VideoFrame();
    virtual ~I420VideoFrame();
    
    virtual int CreateEmptyFrame(int width,
                          int height,
                          int stride_y,
                          int stride_u,
                          int stride_v);
    // CreateFrame: Sets the frame's members and buffers. If required size is
    // bigger than allocated one, new buffers of adequate size will be allocated.
    // Return value: 0 on success, -1 on error.
    virtual int CreateFrame(const uint8_t* buffer_y,
                            const uint8_t* buffer_u,
                            const uint8_t* buffer_v,
                            int width, int height,
                            int stride_y, int stride_u, int stride_v);
    
    // Get pointer to buffer per plane.
    virtual uint8_t* buffer(PlaneType type);
    // Overloading with const.
    virtual const uint8_t* buffer(PlaneType type) const;
    
    // Get allocated stride per plane.
    virtual int stride(PlaneType type) const;
    
    // Get frame width.
    virtual int width() const {return width_;}
    
    // Get frame height.
    virtual int height() const {return height_;}
    
    // Reset underlying plane buffers sizes to 0. This function doesn't
    // clear memory.
    virtual void Reset();
    
protected:
    // Verifies legality of parameters.
    // Return value: 0 on success, -1 on error.
    virtual int CheckDimensions(int width, int height,
                                int stride_y, int stride_u, int stride_v);
    
private:
    // Get the pointer to a specific plane.
    const Plane* GetPlane(PlaneType type) const;
    // Overloading with non-const.
    Plane* GetPlane(PlaneType type);
  
protected:
    Plane y_plane_;
    Plane u_plane_;
    Plane v_plane_;
    int width_;
    int height_;
};  // I420VideoFrame
class NativeVideoFrame:public I420VideoFrame
{
public:
    NativeVideoFrame();
    int CreateFrame(void* nativeframe);
    
    int native2i420();
    void* native_handle();
    void Reset();
private:
    void* native_frame_;
};
#endif /* VideoFrame_h */
