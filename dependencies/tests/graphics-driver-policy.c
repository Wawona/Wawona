#include "WWNSettings.h"

#include <assert.h>
#include <string.h>

int main(void)
{
    WWNSettingsConfig config = {0};
    strcpy(config.vulkanDriver, "turnip");
    strcpy(config.openglDriver, "angle");
    WWNSettings_UpdateConfig(&config);

    WWNGraphicsDriverSelection selection =
        WWNSettings_ResolveGraphicsDriverSelection();
    assert(strcmp(selection.vulkanDriver, "system") == 0);
    assert(strcmp(selection.openGLDriver, "angle") == 0);
    assert(selection.vulkanEnabled);
    assert(selection.openGLEnabled);

    strcpy(config.vulkanDriver, "none");
    strcpy(config.openglDriver, "none");
    WWNSettings_UpdateConfig(&config);
    selection = WWNSettings_ResolveGraphicsDriverSelection();
    assert(!selection.vulkanEnabled);
    assert(!selection.openGLEnabled);

    strcpy(config.vulkanDriver, "swiftshader");
    strcpy(config.openglDriver, "system");
    WWNSettings_UpdateConfig(&config);
    selection = WWNSettings_ResolveGraphicsDriverSelection();
    assert(strcmp(selection.vulkanDriver, "swiftshader") == 0);
    assert(strcmp(selection.openGLDriver, "system") == 0);
    return 0;
}
