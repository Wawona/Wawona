# WWN: Wawona Tunnel Tree identity

This draft supersedes the earlier W and W! treatments. The identity is WWN,
a custom three-letter monogram carved into a simplified sequoia trunk. The
open arch at its base represents the historic drive-through tunnel. The
Wawona Tree stood in Yosemite's Mariposa Grove and fell in 1969.

Historical reference: https://www.nps.gov/seki/faqtunnel.htm

## Design recommendation

Start with one clear visual idea: the sequoia and its passage. Draw an original,
optically balanced vector mark that works in a single color. The custom WWN
letterforms are part of the symbol, rather than a caption in a stock font.
Keep the trunk and arch broad; use no car illustration, fine bark texture,
sparks, or painted lighting. Those details weaken small-size recognition.

Separate the permanent identity from its app-icon material. WWN-logo.svg is
the flat, transparent identity. Wawona.icon adds native Liquid Glass to the
same geometry. Icon Composer supplies edge lighting, translucency and shadow.
The copper tree, slate background and warm interior form a restrained palette.
This is an original Apple-aligned design recommendation, not an Apple design.

Design basis: https://developer.apple.com/design/human-interface-guidelines/app-icons/
Workflow: https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer

## Layer construction

- Sequoia face: one glass layer with real alpha cutouts for WWN and the tunnel.
- Carving depth: an opaque inset edge behind the wood face.
- Interior: a dedicated scene-linear, 32-bit floating-point RGBA OpenEXR layer,
  placed behind the other two groups and annotated for Liquid Glass.

HDR reference white is 1.0; peak red is 2.0, one stop above reference white.
The EXR was reopened and its float values verified. Apple Icon Composer 1.6
successfully rendered the package. Actual HDR display brightness is unmeasured;
the PNG previews are SDR. interior-sdr.png is a companion for SDR-only use.

## Deliverables and checks

WWN-logo.svg and WWN-logo.png are transparent identity assets. flat.png is an
opaque 1024-pixel SDR app artwork export. design-preview.png compares the
native glass icon with its single-color identity. preview-light.png,
preview-dark.png, preview-mono.png, preview-watch.png and preview-small.png
are Apple's native renditions, including a 64-pixel check.

The schema and asset-reference validation pass. Apple's renderer passes all
five previews. The custom WWN lettering was checked at 64 pixels. Production
Apple catalogs and Android assets remain unchanged while the draft is reviewed.
