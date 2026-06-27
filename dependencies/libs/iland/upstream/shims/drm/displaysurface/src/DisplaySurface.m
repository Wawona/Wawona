//
//  DisplaySurface.m
//  Hypervisor
//

#import "DisplaySurface.h"
#import <Foundation/Foundation.h>

// ---------------------------------------------------------------------------
// Format tables
// ---------------------------------------------------------------------------

static const uint32_t s_bytesPerElement[] = {
    [kWSPixelFormatL8   - 1] = 1,
    [kWSPixelFormatL16  - 1] = 2,
    [kWSPixelFormatYUV422-1] = 2,
    [kWSPixelFormatBGRA - 1] = 4,
    [kWSPixelFormatARGB2101010-1] = 4,
    [kWSPixelFormatRGBA64 - 1] = 8,
    [kWSPixelFormatRGBAh - 1] = 8,
    [kWSPixelFormatRGBAf - 1] = 16,
    [kWSPixelFormatW30r - 1] = 4,
    [kWSPixelFormatW40a - 1] = 8,
    [kWSPixelFormatB3A8 - 1] = 5,
};

static const uint32_t s_iosurfaceFormat[] = {
    [kWSPixelFormatL8   - 1] = 'L008',
    [kWSPixelFormatL16  - 1] = 'L008',
    [kWSPixelFormatYUV422-1] = '2vuy',
    [kWSPixelFormatBGRA - 1] = 'BGRA',
    [kWSPixelFormatARGB2101010-1] = 'l10r',
    [kWSPixelFormatRGBA64 - 1] = 'l64r',
    [kWSPixelFormatRGBAh - 1] = 'RGhA',
    [kWSPixelFormatRGBAf - 1] = 'RGfA',
    [kWSPixelFormatW30r - 1] = 'w30r',
    [kWSPixelFormatW40a - 1] = 'w40a',
    [kWSPixelFormatB3A8 - 1] = 'b3a8',
};

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

DisplaySurfaceInfo DisplaySurface_create(uint32_t width, uint32_t height, WSPixelFormat fmt)
{
    DisplaySurfaceInfo info = {0};
    if (fmt < 1 || fmt > 11) return info;

    uint32_t bpe  = s_bytesPerElement[fmt - 1];
    uint32_t fcc  = s_iosurfaceFormat[fmt - 1];

    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    props[(id)kIOSurfaceWidth]           = @(width);
    props[(id)kIOSurfaceHeight]          = @(height);
    props[(id)kIOSurfaceBytesPerElement] = @(bpe);
    props[(id)kIOSurfacePixelFormat]     = @(fcc);
    props[@"IOSurfaceCacheMode"]         = @(0x700);

    IOSurfaceRef surf = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    if (!surf) return info;

    info.surface         = surf;
    info.width           = width;
    info.height          = height;
    info.pixelFormat     = fcc;
    info.bytesPerElement = bpe;
    info.wsFormat        = fmt;
    return info;
}

void DisplaySurface_destroy(DisplaySurfaceInfo *info)
{
    if (info->surface) {
        CFRelease(info->surface);
        info->surface = NULL;
    }
    memset(info, 0, sizeof(*info));
}
