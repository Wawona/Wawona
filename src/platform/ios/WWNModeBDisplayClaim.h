#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#if WWN_MODE_B
/// Digitizer in the IOMFB overlay's view space (window points).
/// state: 0=up, 1=down, 2=motion.
typedef void (*WWNModeBHidSink)(int32_t touchId, int state, double viewX, double viewY);

void wwn_modeb_set_hid_sink(WWNModeBHidSink _Nullable sink);

/// Park iOS render clients we can reach, steal digitizer HID, and hold
/// IOMFB scanout. Never touches watchdogd. Restore must call release.
int32_t wwn_modeb_claim_host(void);
int32_t wwn_modeb_release_host(void);
int32_t wwn_modeb_claim_active(void);
#endif

NS_ASSUME_NONNULL_END
