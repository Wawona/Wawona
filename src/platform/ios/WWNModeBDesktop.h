#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceRef.h>

NS_ASSUME_NONNULL_BEGIN

#if WWN_MODE_B
int32_t wwn_modeb_desktop_start(uint32_t *outWidth, uint32_t *outHeight);
int32_t wwn_modeb_desktop_set_profiles_json(const char *json);
int32_t wwn_modeb_desktop_present_iosurface(IOSurfaceRef surface,
                                            uint32_t width,
                                            uint32_t height);
/// Acquire IOMFB surface (same as greeter), blit BGRA src into the top-left,
/// present. Prefer this over a second IOSurfaceCreate for Relay proofs.
int32_t wwn_modeb_desktop_present_bgra(const uint8_t *pixels, uint32_t srcWidth,
                                       uint32_t srcHeight);
int32_t wwn_modeb_desktop_handle_touch(float x, float y, uint8_t ended);
int32_t wwn_modeb_desktop_recover_to_greeter(void);
int32_t wwn_modeb_desktop_enter_session(void);
int32_t wwn_modeb_desktop_size(uint32_t *outWidth, uint32_t *outHeight);
int32_t wwn_modeb_desktop_bind_iland_present(void);
typedef int32_t (*WWNModeBPresentSessionFn)(uint32_t session_id, uint8_t kind,
                                            const char *_Nullable label);
void wwn_modeb_desktop_set_present_session(
    WWNModeBPresentSessionFn _Nullable fn);
int32_t wwn_modeb_desktop_adopt_text_sessions(void);
uint32_t wwn_modeb_desktop_phase(void);
const char *wwn_modeb_desktop_last_error(void);
int32_t wwn_modeb_desktop_restore(void);
int32_t wwn_modeb_desktop_refresh(void);
int32_t wwn_modeb_desktop_front_surface(void *_Nullable *_Nonnull outSurface,
                                        uint32_t *_Nonnull outId,
                                        uint32_t *_Nonnull outWidth,
                                        uint32_t *_Nonnull outHeight);
int32_t wwn_modeb_desktop_last_present(void);

/// Digitizer in the IOMFB overlay's view space (window points).
/// state: 0=up, 1=down, 2=motion.
typedef void (*WWNModeBHidSink)(int32_t touchId, int state, double viewX,
                                double viewY);
void wwn_modeb_set_hid_sink(WWNModeBHidSink _Nullable sink);
int32_t wwn_modeb_claim_host(void);
int32_t wwn_modeb_release_host(void);
int32_t wwn_modeb_claim_active(void);
#endif

NS_ASSUME_NONNULL_END
