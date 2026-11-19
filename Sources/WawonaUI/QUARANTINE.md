# Dual-run quarantine (Exact M8)

Exact owns product Machines/Settings chrome (`apps/wawona/app.contract`).

This `Sources/WawonaUI` tree is the dual-run host until M8:

1. Exact hosts green on ALL_TARGETS matrix cells that need chrome.
2. Darwin/`SceneDelegate` stop hosting `WawonaRootView` for product.
3. Delete this chrome (keep Present glue under `Sources/WawonaApple` until Exact
   Present modules own compositor poll).

Do not grow Machines/Settings here. New chrome goes in Exact Contract.
