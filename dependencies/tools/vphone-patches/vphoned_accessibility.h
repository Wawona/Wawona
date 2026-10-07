/*
 * vphoned_accessibility — Accessibility tree query over vsock.
 *
 * Handles accessibility_tree. Currently a stub — requires XPC research
 * to properly query the accessibility tree from a daemon context.
 */

#pragma once
#import <Foundation/Foundation.h>

/// Handle an accessibility_tree command. Returns a response dict.
NSDictionary *vp_handle_accessibility_command(NSDictionary *msg);
