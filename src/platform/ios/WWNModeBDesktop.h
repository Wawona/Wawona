#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceRef.h>

NS_ASSUME_NONNULL_BEGIN

#if WWN_MODE_B
int32_t wwn_modeb_desktop_start(uint32_t *outWidth, uint32_t *outHeight);
int32_t wwn_modeb_desktop_set_profiles_json(const char *json);
int32_t wwn_modeb_desktop_present_iosurface(IOSurfaceRef surface,
                                            uint32_t width,
                                            uint32_t height);
int32_t wwn_modeb_desktop_handle_touch(float x, float y, uint8_t ended);
int32_t wwn_modeb_desktop_recover_to_greeter(void);
int32_t wwn_modeb_desktop_adopt_text_sessions(void);
uint32_t wwn_modeb_desktop_phase(void);
const char *wwn_modeb_desktop_last_error(void);
int32_t wwn_modeb_desktop_restore(void);
#endif

NS_ASSUME_NONNULL_END
