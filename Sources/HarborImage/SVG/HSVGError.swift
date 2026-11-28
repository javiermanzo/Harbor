//
//  HSVGError.swift
//  HarborImage
//
//  Created by Javier Manzo on 27/11/2026.
//

import Foundation

/// The reason an SVG document could not be parsed or rendered. The renderer never draws a
/// document it does not fully understand: anything outside the supported subset throws instead
/// of rendering silently wrong.
enum HSVGError: Error, Equatable, Sendable {
    /// The document is not well-formed XML, has no `<svg>` root, carries an unparsable value in
    /// a place that needs one (a transform, a CSS block), or has a `<use>` cycle. Reported as
    /// `HImageError.decodingFailed`. The string describes what failed.
    case malformed(String)
    /// The document uses a feature outside the supported subset (filters, masks, text, patterns,
    /// images, animation, markers, complex CSS selectors, ...). The string names the element,
    /// attribute or feature.
    case unsupported(String)
    /// The document carries content that is never processed for safety: external (`SYSTEM`,
    /// `PUBLIC`), parameter (`%`), unparsed or nested entity declarations, more than 32 entities
    /// or a value over 4,096 characters, scripts, event attributes, references outside the
    /// document or `@import`. The string names what was found.
    case unsafe(String)
    /// The requested raster is above 100 megapixels or cannot be created, the document has more
    /// than 200,000 elements (counting `use` instances), nests them deeper than 256 levels in the
    /// XML or 64 when rendered (groups, `use`, nested viewports), or draws more than 2,000,000
    /// path segments (counting `use` instances).
    case tooLarge
}
