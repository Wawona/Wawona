# WWN interlocking monogram

Current direction: WWN is the iconography. This supersedes the illustrative
trunk with WWN lettering. Three original letter silhouettes overlap and share
edges to form a single compact identity. The contours are custom vector paths,
not live text or a stock-font caption.

## Design reasoning

The chosen reference principles are a distinctive letter silhouette, overlapping
planes, disciplined spacing and a limited palette. PayPal's overlapping letters
and Venmo's custom letter illustrate these principles. Their outlines and brand
colors are not copied. WWN keeps its own warm sequoia palette over deep slate.
The rounded lower counters suggest the Wawona tunnel without a separate tree,
car or landscape illustration.

References inspected:
https://apps.apple.com/us/app/paypal-pay-send-save/id283646709
https://apps.apple.com/us/app/venmo/id351727428

Apple's approach is to define a simple, recognizable identity first, then
annotate its separate layers for native glass materials. Maintain a readable
single-color silhouette, clean foreground edges, adequate margin and legible
small-size counters. Let the system supply specular lighting and shadows.
Do not bake a fake glass effect into the identity artwork.

https://developer.apple.com/design/human-interface-guidelines/app-icons/
https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer

## Construction and verification

Wawona.icon contains three native glass groups for the front W, middle W and
rear N. A fourth dedicated OpenEXR layer provides internal HDR light behind
those materials. The HDR source has 32-bit float RGBA, scene-linear Rec.709/D65,
straight alpha, reference white 1.0 and verified peak red 2.0.

The identity remains separate from its native material treatment:
wwn.svg is the original three-part vector; logo-mono.svg is its one-color use;
flat.png is opaque SDR artwork; the preview PNGs are native glass renditions.
The PNGs are SDR. Installed-device HDR brightness is unmeasured.

Schema and asset references pass validation. Apple's installed Icon Composer
1.6 renders light, dark, monochrome, watch and 64-pixel previews. This package
uses compatible 1.x controls. OS 27-specific refraction and render-generation
comparisons require Icon Composer 2 and have not been verified on this host.

Production product catalogs remain unchanged while the design is reviewed.
