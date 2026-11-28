# SVG

HarborImage renders SVG with its own renderer (`XMLParser` + Core Graphics, no dependency; Core SVG is private API). It renders a documented subset and **never draws a document it does not fully understand**:

- outside the subset, or with unsafe content → `.unsupportedFormat`;
- malformed XML, a `<use>` cycle or an unclosed CSS block → `.decodingFailed`;
- size and work limits → `.tooManyPixels`.

## Sizing

- Intrinsic size: absolute `width`/`height` (unitless, `px`, `pt`, `pc`, `mm`, `cm`, `in`, `em` and `rem` = 16, `ex` = 8), completed from the `viewBox` ratio when only one is set, else the `viewBox` size, else 300×150. Percentages fall back to the `viewBox`.
- Without a target the SVG is rasterized at its intrinsic size (1 pixel per point). Set `targetSize` (or `.downsampling(to:)` on `HImageView`, or make `.resize(to:)` the first processor) to render it sharp at the displayed size; vector images are enlarged as needed.
- The original SVG is what the disk cache keeps (also with processors or an `encoding`); each size is rasterized from it.

## Supported

| Area | Supported |
|---|---|
| Structure | `svg` (root and nested, with `x`, `y`, `width`, `height`, `viewBox`, every `preserveAspectRatio`, a `transform` on the root), `g`, `a`, `defs`, `symbol`, `use` (`href` / `xlink:href="#id"`, `x`, `y`, `width`, `height`; a referenced `<svg>` keeps its own size unless the `use` sets one), `switch` (first child that is not `foreignObject`) |
| Ignored | `title`, `desc`, `metadata`, elements of other namespaces (`sodipodi:`, `inkscape:`, ...) and unknown elements |
| Shapes | `rect` (with `rx`/`ry`), `circle`, `ellipse`, `line`, `polyline`, `polygon`, `path` (every command, relative and absolute, arcs, compact numbers) |
| Lengths | unitless, `px`, `pt`, `pc`, `mm`, `cm`, `in`, `em`, `rem`, `ex`, `%`, `vw`, `vh`, `vmin`, `vmax` |
| Transforms | `matrix`, `translate`, `scale`, `rotate` (with center), `skewX`, `skewY`, lists |
| Paint | `fill`, `stroke`, `none`, `currentColor`, `color`, `url(#id) fallback`; colors `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, `hsl()`, `hsla()`, every CSS keyword, `transparent` |
| Stroke | `stroke-width`, `stroke-linecap`, `stroke-linejoin`, `stroke-miterlimit`, `stroke-dasharray`, `stroke-dashoffset`, `paint-order: normal`, `vector-effect: none` |
| Opacity | `opacity` (the group composited as a whole), `fill-opacity`, `stroke-opacity` |
| Gradients | `linearGradient`, `radialGradient` (`fx`, `fy`, `fr`; `r="0"` paints the last stop), `gradientUnits`, `gradientTransform`, `href` inheritance, stops with `stop-color` / `stop-opacity`, `spreadMethod="pad"` |
| Clipping | `clipPath` (`clipPathUnits`, `transform`): the union of its shapes and `use` of shapes, each filled with its own `clip-rule`; other children (groups) are skipped, as the spec allows only shapes, text and `use` there. Several shapes need iOS 16 / macOS 13 (`.unsupportedFormat` on iOS 15); a missing reference does not clip; an empty clip path hides the element. |
| Other | `fill-rule`, `display`, `visibility`, `inherit` |
| CSS | `<style>` (CDATA too) with type, class, id and `*` selectors (and a type combined with a class or an id), comma lists, `!important`; the `style` attribute. Order: presentation attributes < style sheet (by specificity) < `style` attribute < `!important` |

## Rejected

| `.unsupportedFormat` (unsupported) | `.unsupportedFormat` (unsafe) |
|---|---|
| `text`, `tspan`, `textPath`, `font`, `glyph` | `script`, `handler`, event attributes (`onload`, ...) |
| `image`, `foreignObject`, `video`, `audio`, `iframe`, `canvas` | `use` pointing outside the document |
| `filter` / `filter=`, `mask` / `mask=` | External (`SYSTEM`, `PUBLIC`), parameter (`%`), unparsed and nested entities (expansion bombs), more than 32 entities or a value over 4,096 characters, wherever they appear in the document |
| `pattern` paints, markers | `@import` |
| SMIL animation (`animate*`, `set`), also inside shapes, gradients and stops | |
| `spreadMethod="reflect"` / `"repeat"` | |
| `overflow: visible` / `auto` on a nested `<svg>` or a `<symbol>`, `paint-order` other than the default, `vector-effect`, `transform-origin` | |
| CSS combinators, attribute selectors, pseudo-classes, at-rules other than `@charset`, the CSS `transform` property | |

Simple text entities (as exported by Illustrator) are accepted.

## Limits

All fail with `.tooManyPixels`:

- more than 200,000 elements (counting `use` instances);
- XML nested deeper than 256 levels, or more than 64 levels when rendered (groups, `use` instances and nested viewports add up, so a chain of `use` cannot overflow the stack);
- more than 2,000,000 path segments drawn (counting `use` instances), so a small document cannot keep the CPU busy for seconds;
- a raster above `setMaxImagePixels` (100 MP by default, never above 100 MP).

## A fuller renderer

To support more of SVG, register an `HImageDecoder` whose `format` is `.svg` with `await HarborImage.registerDecoder(_:)`: registered decoders are asked first.
