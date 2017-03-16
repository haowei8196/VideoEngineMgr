/*
 *  Copyright (c) 2013 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#ifndef VIDEO_RENDER_IOS_RENDER_VIEW_H_
#define VIDEO_RENDER_IOS_RENDER_VIEW_H_

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include "open_gles20.h"


@interface VideoRenderIosView : UIView
@property (nonatomic, readonly) GLint drawableWidth;
@property (nonatomic, readonly) GLint drawableHeight;
- (BOOL)createContext;
- (void)resetViewport;
- (BOOL)presentFramebuffer;
- (BOOL)renderFrame:(I420VideoFrame*)frameToRender;
- (BOOL)setCoordinatesForZOrder:(const float)zOrder
                           Left:(const float)left
                            Top:(const float)top
                          Right:(const float)right
                         Bottom:(const float)bottom;

@property(nonatomic, retain) EAGLContext* context;

@end

#endif  // VIDEO_RENDER_IOS_RENDER_VIEW_H_
