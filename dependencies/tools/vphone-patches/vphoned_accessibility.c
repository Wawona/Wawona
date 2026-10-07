/*
 * vphoned_accessibility — Accessibility tree query over vsock (Wawona).
 *
 * Full AXRuntime / SpringBoard injection remains research. This implementation
 * returns an interactive node list from LSApplicationWorkspace (installed apps)
 * so agent-device can emit @eN refs against the jailbroken research VM.
 */

#import "vphoned_accessibility.h"
#import "vphoned_protocol.h"
#import "vphoned_apps.h"

#include <math.h>

NSDictionary *vp_handle_accessibility_command(NSDictionary *msg) {
  id reqId = msg[@"id"];
  (void)msg;

  NSDictionary *listReq = @{
    @"t" : @"app_list",
    @"id" : reqId ?: @"0",
    @"filter" : @"user",
  };
  NSDictionary *listResp = vp_handle_apps_command(listReq);
  NSArray *apps = listResp[@"apps"];
  if (![apps isKindOfClass:[NSArray class]]) {
    NSMutableDictionary *r = vp_make_response(@"err", reqId);
    r[@"msg"] = @"accessibility_tree: app_list unavailable";
    return r;
  }

  const double screenW = 1290.0;
  const double screenH = 2796.0;
  const double cols = 4.0;
  const double icon = fmin(screenW, screenH) * 0.14;
  const double left = screenW * 0.08;
  const double top = screenH * 0.18;
  const double gapX = (screenW - left * 2 - icon * cols) / (cols - 1);
  const double gapY = icon * 0.55;

  NSMutableArray *nodes = [NSMutableArray array];
  NSUInteger i = 0;
  for (NSDictionary *app in apps) {
    if (![app isKindOfClass:[NSDictionary class]])
      continue;
    double col = (double)(i % (NSUInteger)cols);
    double row = (double)(i / (NSUInteger)cols);
    double x = left + col * (icon + gapX);
    double y = top + row * (icon + gapY);
    [nodes addObject:@{
      @"index" : @(i),
      @"type" : @"app_icon",
      @"role" : @"button",
      @"label" : app[@"name"] ?: @"",
      @"identifier" : app[@"bundle_id"] ?: @"",
      @"rect" : @{
        @"x" : @(x),
        @"y" : @(y),
        @"width" : @(icon),
        @"height" : @(icon),
      },
      @"enabled" : @YES,
      @"hittable" : @YES,
      @"visible" : @YES,
      @"depth" : @0,
      @"bundle_id" : app[@"bundle_id"] ?: @"",
      @"pid" : app[@"pid"] ?: @0,
    }];
    i++;
  }

  NSMutableDictionary *r = vp_make_response(@"accessibility_tree", reqId);
  r[@"ok"] = @YES;
  r[@"nodes"] = nodes;
  r[@"screenWidth"] = @(screenW);
  r[@"screenHeight"] = @(screenH);
  r[@"warning"] =
      @"vphoned accessibility_tree: app_list icon-grid heuristic (AXRuntime TBD)";
  return r;
}
