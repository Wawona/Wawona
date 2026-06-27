//
//  DisplaySurface.h
//  Hypervisor
//
//  IOSurface creation/destruction helpers compatible with the
//  CAWindowServer display pipeline (WSPixelFormat).
//

#pragma once

#import <IOSurface/IOSurface.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// WSPixelFormat  (from CoreDisplay PixelFormat.cc)
// ---------------------------------------------------------------------------

typedef enum WSPixelFormat {
    kWSPixelFormatL8          = 1,
    kWSPixelFormatL16         = 2,
    kWSPixelFormatYUV422      = 3,
    kWSPixelFormatBGRA        = 4,
    kWSPixelFormatARGB2101010 = 5,
    kWSPixelFormatRGBA64      = 6,
    kWSPixelFormatRGBAh       = 7,
    kWSPixelFormatRGBAf       = 8,
    kWSPixelFormatW30r        = 9,
    kWSPixelFormatW40a        = 10,
    kWSPixelFormatB3A8        = 11,
} WSPixelFormat;

// ---------------------------------------------------------------------------
// DisplaySurfaceInfo
// ---------------------------------------------------------------------------

typedef struct DisplaySurfaceInfo {
    IOSurfaceRef    surface;
    uint32_t        width;
    uint32_t        height;
    uint32_t        pixelFormat;        // IOSurface FourCC
    uint32_t        bytesPerElement;
    WSPixelFormat   wsFormat;
} DisplaySurfaceInfo;

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

/// Create an IOSurface compatible with the CAWindowServer display pipeline.
DisplaySurfaceInfo DisplaySurface_create(uint32_t width, uint32_t height, WSPixelFormat fmt);

/// Release the IOSurface and zero the struct.
void DisplaySurface_destroy(DisplaySurfaceInfo *info);
