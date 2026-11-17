//
//  CacheControlDirectives.swift
//  Harbor
//
//  Created by Javier Manzo on 16/11/2026.
//

import Foundation

/// Recognized `Cache-Control` directives. `s-maxage`, `proxy-revalidate`, `public` and `private`
/// are parsed for completeness; they do not change behavior because Harbor's custom cache and
/// `URLCache` are private caches, to which the shared-cache directives do not apply.
struct CacheControlDirectives {
    /// The maximum age in seconds specified by `max-age`.
    var maxAge: Int?
    /// The maximum age in seconds specified by `s-maxage`.
    var sMaxAge: Int?
    /// Whether `no-cache` is specified.
    var noCache = false
    /// Whether `no-store` is specified.
    var noStore = false
    /// Whether `must-revalidate` is specified.
    var mustRevalidate = false
    /// Whether `proxy-revalidate` is specified.
    var proxyRevalidate = false
    /// The window in seconds for `stale-while-revalidate`.
    var staleWhileRevalidate: Int?
    /// The window in seconds for `stale-if-error`.
    var staleIfError: Int?
    /// Whether `public` is specified.
    var isPublic = false
    /// Whether `private` is specified.
    var isPrivate = false
}
