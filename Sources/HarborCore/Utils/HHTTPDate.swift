//
//  HHTTPDate.swift
//  HarborCore
//
//  Created by Javier Manzo on 16/10/2026.
//

import Foundation

/// Parser of HTTP-date header values, shared by the cache (`Expires`, `Last-Modified`, `Date`)
/// and the `Retry-After` handling.
package enum HHTTPDate {
    /// HTTP-date formatters for the three formats allowed by RFC 9110 (IMF-fixdate, RFC 850, asctime),
    /// one instance per format so the date format is never mutated between parses.
    private static let formatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()

    /// Parses an HTTP-date header value.
    /// - Parameter string: The header value, in any of the three RFC 9110 date formats.
    /// - Returns: The date, or `nil` when the value matches none of them.
    package static func parse(_ string: String) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}
