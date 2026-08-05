//
//  HFormValue.swift
//  Harbor
//
//  Created by Javier Manzo on 05/08/2026.
//

import Foundation

/// A typed value for a multipart form field.
public enum HFormValue: Sendable {
    /// A plain text form field.
    case text(String)
    /// A file form field. The file contents are read from `url`; when `mimeType` is nil no
    /// `Content-Type` part header is sent, and when `fileName` is nil the URL's last path
    /// component is used as the filename.
    case file(url: URL, mimeType: String?, fileName: String?)
}
