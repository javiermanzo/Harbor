//
//  ImageDemo.swift
//  HarborExample
//
//  URLs and images generated in code shared by the HarborImage demo sections
//

import SwiftUI
import UIKit

@MainActor
enum ImageDemo {
    /// Photos from picsum.photos (stable ids, any size).
    static let photos = (10..<40).map { "https://picsum.photos/id/\($0)/600/600" }
    /// Answered by a mock (debug builds), so the failure is the same every time.
    static let brokenURL = "https://images.example.com/missing.png"
    /// The failing main URL of the fallback demo, answered by its own mock (debug builds); the
    /// fallback image is cached under it.
    static let movedURL = "https://images.example.com/moved.png"
    /// A small SVG inlined as a `data:` URL, so it works offline.
    static let svgURL = "data:image/svg+xml;utf8," + (#"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">\#
    <stop offset="0" stop-color="#4f8cff"/><stop offset="1" stop-color="#a64fff"/></linearGradient></defs>\#
    <circle cx="12" cy="12" r="11" fill="url(#g)"/><path d="M7 12.5l3 3 7-7" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
    """#.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
    /// Only loaded by the cache-only demo, so nothing else puts it in the cache.
    static let cacheOnlyURL = "https://picsum.photos/id/1015/600/600"
    /// An animated GIF.
    static let gifURL = "https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_%28large%29.gif"

    /// The size photos are resized to before the processors of a tile run.
    static let square = CGSize(width: 240, height: 240)

    /// A small badge drawn in code, used by the overlay processor.
    static let badge: CGImage = {
        let size = CGSize(width: 120, height: 120)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemOrange.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            UIColor.white.setStroke()
            context.cgContext.setLineWidth(10)
            context.cgContext.strokeEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5))
        }
        return image.cgImage!
    }()

    /// A five-pointed star in unit coordinates (`0...1`, origin at the top left), the coordinate
    /// space of `HImageMaskShape.path(_:id:)`.
    static let starPath: CGPath = {
        let path = CGMutablePath()
        let center = CGPoint(x: 0.5, y: 0.52)
        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? 0.5 : 0.21
            let angle = Double(index) * .pi / 5 - .pi / 2
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }()

    /// A heart in unit coordinates, drawn with Bézier curves.
    static let heartPath: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.5, y: 0.92))
        path.addCurve(to: CGPoint(x: 0.04, y: 0.34), control1: CGPoint(x: 0.2, y: 0.7), control2: CGPoint(x: 0.04, y: 0.55))
        path.addCurve(to: CGPoint(x: 0.5, y: 0.2), control1: CGPoint(x: 0.04, y: 0.05), control2: CGPoint(x: 0.4, y: 0.02))
        path.addCurve(to: CGPoint(x: 0.96, y: 0.34), control1: CGPoint(x: 0.6, y: 0.02), control2: CGPoint(x: 0.96, y: 0.05))
        path.addCurve(to: CGPoint(x: 0.5, y: 0.92), control1: CGPoint(x: 0.96, y: 0.55), control2: CGPoint(x: 0.8, y: 0.7))
        path.closeSubpath()
        return path
    }()

    /// A mask image whose alpha fades from opaque in the center to transparent at the edges:
    /// `HImageMaskShape.image(_:id:)` keeps the photo where the mask is opaque.
    static let vignetteMask: CGImage = {
        let size = CGSize(width: 120, height: 120)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.35, 1])!
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width / 2, options: [])
        }
        return image.cgImage!
    }()
}
