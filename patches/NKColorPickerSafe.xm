// NKTouch v0.7.7 safe, bounded pixel/color backend.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Keep upstream TASK_COLOR_PICKER (23) / TASK_COLOR_SEARCHER (28) wire format.
// Coordinates are *physical screenshot pixels*, matching ZXTouch native HID
// coordinates in portrait; no implicit point/scale/rotation conversion.
// This replaces the previous unchecked crop/context/allocation paths.
#include "ColorPicker.h"
#include "Screen.h"
#import <CoreGraphics/CoreGraphics.h>
#import <limits.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>

#define NK_COLOR_SCAN_MAX_BYTES (96U * 1024U * 1024U)
#define NK_COLOR_MAX_ARG 10000
#define NK_COLOR_MAX_SKIP 1000

static void NKColorError(NSError **out, NSString *code) {
    if (!out) return;
    NSString *message = [NSString stringWithFormat:@"-1;;%@\r\n", code];
    *out = [NSError errorWithDomain:@"com.nk.nktouch.color"
                              code:999
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}

// NSScanner/NSString.intValue can accept non-digits or partial numbers.
// Treat the IPC payload as untrusted, requiring strict non-negative integers.
static BOOL NKColorParseNumber(NSString *text, int maximum, int *value) {
    if (!text || text.length == 0 || text.length > 10 || !value) return NO;
    uint64_t sum = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar ch = [text characterAtIndex:i];
        if (ch < '0' || ch > '9') return NO;
        sum = sum * 10 + (unsigned)(ch - '0');
        if (sum > (uint64_t)maximum) return NO;
    }
    *value = (int)sum;
    return YES;
}

static BOOL NKColorCopyPixels(CGImageRef image, CGRect region,
                              uint8_t **pixels, size_t *rowBytes) {
    if (!image || !pixels || !rowBytes) return NO;
    size_t width = (size_t)region.size.width;
    size_t height = (size_t)region.size.height;
    if (width == 0 || height == 0 || width > SIZE_MAX / 4) return NO;
    size_t stride = width * 4;
    if (height > SIZE_MAX / stride || stride * height > NK_COLOR_SCAN_MAX_BYTES)
        return NO;

    CGImageRef crop = CGImageCreateWithImageInRect(image, region);
    if (!crop) return NO;
    uint8_t *buffer = (uint8_t *)calloc(height, stride);
    if (!buffer) { CGImageRelease(crop); return NO; }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    if (!space) { free(buffer); CGImageRelease(crop); return NO; }
    CGContextRef bitmap = CGBitmapContextCreate(
        buffer, width, height, 8, stride, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!bitmap) { free(buffer); CGImageRelease(crop); return NO; }

    CGContextSetInterpolationQuality(bitmap, kCGInterpolationNone);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), crop);
    CGContextRelease(bitmap);
    CGImageRelease(crop);
    *pixels = buffer;
    *rowBytes = stride;
    return YES;
}

static BOOL NKColorPixel(CGImageRef image, int x, int y,
                          uint8_t *r, uint8_t *g, uint8_t *b) {
    if (!image || x < 0 || y < 0 ||
        (size_t)x >= CGImageGetWidth(image) ||
        (size_t)y >= CGImageGetHeight(image)) return NO;
    uint8_t *pixel = NULL;
    size_t stride = 0;
    if (!NKColorCopyPixels(image, CGRectMake(x, y, 1, 1), &pixel, &stride))
        return NO;
    (void)stride;
    *r = pixel[0]; *g = pixel[1]; *b = pixel[2];
    free(pixel);
    return YES;
}

NSDictionary *getRGBFromRawData(UInt8 *eventData, NSError **error) {
    NSString *raw = eventData ? [NSString stringWithUTF8String:(const char *)eventData] : nil;
    NSArray<NSString *> *args = [raw componentsSeparatedByString:@";;"];
    int x = 0, y = 0;
    if (args.count != 2 ||
        !NKColorParseNumber(args[0], NK_COLOR_MAX_ARG, &x) ||
        !NKColorParseNumber(args[1], NK_COLOR_MAX_ARG, &y)) {
        NKColorError(error, @"COLOR_INVALID_COORDINATES");
        return nil;
    }
    CGImageRef screen = [Screen createScreenShotCGImageRef];
    if (!screen) {
        NKColorError(error, @"COLOR_CAPTURE_FAILED");
        return nil;
    }
    if ((size_t)x >= CGImageGetWidth(screen) ||
        (size_t)y >= CGImageGetHeight(screen)) {
        CGImageRelease(screen);
        NKColorError(error, @"COLOR_OUT_OF_BOUNDS");
        return nil;
    }
    uint8_t r=0, g=0, b=0;
    BOOL ok = NKColorPixel(screen, x, y, &r, &g, &b);
    CGImageRelease(screen);
    if (!ok) {
        NKColorError(error, @"COLOR_PIXEL_READ_FAILED");
        return nil;
    }
    return @{@"red":@(r), @"green":@(g), @"blue":@(b)};
}

NSString *searchRGBFromRawData(UInt8 *eventData, NSError **error) {
    NSString *raw = eventData ? [NSString stringWithUTF8String:(const char *)eventData] : nil;
    NSArray<NSString *> *args = [raw componentsSeparatedByString:@";;"];
    int parsed[12] = {0};
    if (args.count != 12 ||
        !NKColorParseNumber(args[0], 1, &parsed[0]) ||
        parsed[0] != 1) {
        NKColorError(error, @"COLOR_INVALID_SEARCH_REQUEST");
        return nil;
    }
    for (int i=1; i<12; i++) {
        int maximum = (i>=5 && i<=10) ? 255 : (i==11 ? NK_COLOR_MAX_SKIP : NK_COLOR_MAX_ARG);
        if (!NKColorParseNumber(args[(NSUInteger)i], maximum, &parsed[i])) {
            NKColorError(error, @"COLOR_INVALID_SEARCH_REQUEST");
            return nil;
        }
    }
    int x=parsed[1], y=parsed[2], width=parsed[3], height=parsed[4];
    int rmin=parsed[5], rmax=parsed[6], gmin=parsed[7], gmax=parsed[8];
    int bmin=parsed[9], bmax=parsed[10], skip=parsed[11];
    if (rmin>rmax || gmin>gmax || bmin>bmax) {
        NKColorError(error, @"COLOR_INVALID_RGB_RANGE");
        return nil;
    }
    CGImageRef image = [Screen createScreenShotCGImageRef];
    if (!image) { NKColorError(error, @"COLOR_CAPTURE_FAILED"); return nil; }
    size_t sw=CGImageGetWidth(image), sh=CGImageGetHeight(image);
    if ((size_t)x >= sw || (size_t)y >= sh) {
        CGImageRelease(image);
        NKColorError(error, @"COLOR_OUT_OF_BOUNDS");
        return nil;
    }
    // Keep the documented legacy behavior: zero width/height means "rest of
    // the screen". Non-zero regions are clipped, never read out of bounds.
    size_t remainW=sw-(size_t)x, remainH=sh-(size_t)y;
    if (width==0 || (size_t)width>remainW) width=(int)remainW;
    if (height==0 || (size_t)height>remainH) height=(int)remainH;
    NSString *result = [ColorPicker searchRGBFromCGImageRef:image
                                region:CGRectMake(x,y,width,height)
                                redMin:rmin redMax:rmax
                                greenMin:gmin greenMax:gmax
                                blueMin:bmin blueMax:bmax skip:skip];
    CGImageRelease(image);
    if (!result) {
        NKColorError(error, @"COLOR_BUFFER_FAILED");
        return nil;
    }
    return result;
}

@implementation ColorPicker

+ (NSDictionary *)colorAtPositionFromCGImage:(CGImageRef)image
                                          x:(int)x andY:(int)y {
    uint8_t r=0,g=0,b=0;
    if (!NKColorPixel(image,x,y,&r,&g,&b)) return nil;
    return @{@"red":@(r),@"green":@(g),@"blue":@(b)};
}

+ (NSString *)searchRGBFromCGImageRef:(CGImageRef)image
                              region:(CGRect)region
                              redMin:(int)rmin redMax:(int)rmax
                            greenMin:(int)gmin greenMax:(int)gmax
                             blueMin:(int)bmin blueMax:(int)bmax
                                skip:(int)skip {
    if (!image || region.size.width <= 0 || region.size.height <= 0 ||
        region.origin.x < 0 || region.origin.y < 0 || skip < 0 ||
        (size_t)CGRectGetMaxX(region) > CGImageGetWidth(image) ||
        (size_t)CGRectGetMaxY(region) > CGImageGetHeight(image))
        return nil;
    uint8_t *buffer=NULL;
    size_t stride=0;
    if (!NKColorCopyPixels(image,region,&buffer,&stride)) return nil;
    size_t width=(size_t)region.size.width, height=(size_t)region.size.height;
    size_t increment=(size_t)skip+1;
    NSString *found=nil;
    for (size_t cy=0; cy<height; cy+=increment) {
        for (size_t cx=0; cx<width; cx+=increment) {
            const uint8_t *pixel=buffer+cy*stride+cx*4;
            int r=pixel[0],g=pixel[1],b=pixel[2];
            if (r>=rmin && r<=rmax && g>=gmin && g<=gmax && b>=bmin && b<=bmax) {
                found=[NSString stringWithFormat:@"%ld;;%ld;;%d;;%d;;%d",
                    (long)region.origin.x+(long)cx,
                    (long)region.origin.y+(long)cy,r,g,b];
                break;
            }
        }
        if (found) break;
    }
    free(buffer);
    return found ?: @"-1;;-1;;-1;;-1;;-1";
}

@end
