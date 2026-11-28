//
//  HSVGRendererTests.swift
//  HarborImageTests
//
//  The SVG renderer, checked pixel by pixel: sizing, shapes, paths, transforms, paints,
//  gradients, clipping, reuse, CSS, and the main rejections (unsupported and unsafe content,
//  size, depth and work limits).
//

import XCTest
@testable import HarborImage

final class HSVGRendererTests: XCTestCase {

    /// Renders an SVG body inside a 100x100 document at `size`x`size` pixels (100 by default).
    private func render(_ body: String, size: Int = 100, attributes: String = "") throws -> CGImage {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100" \#(attributes)>\#(body)</svg>"#
        return try HSVGDocument(data: Data(svg.utf8)).render(pixelSize: CGSize(width: size, height: size))
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> RGBA {
        TestImages.pixel(image, x: x, y: y)
    }

    private func assertThrows(_ svg: String, _ check: (HSVGError) -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try HSVGDocument(data: Data(svg.utf8))
            XCTFail("Expected an error for \(svg)", file: file, line: line)
        } catch {
            XCTAssertTrue(check(error), "Unexpected \(error)", file: file, line: line)
        }
    }

    // MARK: - Sniffing and Size

    func testSniffing() {
        XCTAssertTrue(HSVGSniffer.isSVG(Data(#"<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8)))
        XCTAssertTrue(HSVGSniffer.isSVG(Data("\u{FEFF}  <!-- icon --><svg></svg>".utf8)))
        XCTAssertFalse(HSVGSniffer.isSVG(Data("<!DOCTYPE html><html><svg></svg></html>".utf8)))
        XCTAssertFalse(HSVGSniffer.isSVG(TestImages.png()))
    }

    func testIntrinsicSize() throws {
        func size(_ attributes: String) throws -> CGSize {
            try HSVGDocument(data: Data(#"<svg xmlns="http://www.w3.org/2000/svg" \#(attributes)/>"#.utf8)).intrinsicSize
        }
        XCTAssertEqual(try size(#"width="40" height="20""#), CGSize(width: 40, height: 20))
        XCTAssertEqual(try size(#"width="12pt" height="1in""#), CGSize(width: 16, height: 96))
        XCTAssertEqual(try size(#"viewBox="0 0 24 12""#), CGSize(width: 24, height: 12))
        XCTAssertEqual(try size(#"width="48" viewBox="0 0 24 12""#), CGSize(width: 48, height: 24))
        XCTAssertEqual(try size(#"width="100%" viewBox="0 0 24 12""#), CGSize(width: 24, height: 12))
        XCTAssertEqual(try size(""), CGSize(width: 300, height: 150))
    }

    func testRenderSizeIsExact() throws {
        let image = try render(#"<rect width="100" height="100" fill="red"/>"#, size: 37)
        XCTAssertEqual(image.width, 37)
        XCTAssertEqual(image.height, 37)
    }

    // MARK: - Shapes

    func testBasicShapes() throws {
        let image = try render("""
        <rect x="0" y="0" width="50" height="50" fill="red"/>
        <circle cx="75" cy="25" r="20" fill="#00ff00"/>
        <ellipse cx="25" cy="75" rx="20" ry="10" fill="blue"/>
        <polygon points="60,60 100,60 100,100 60,100" fill="black"/>
        """)
        XCTAssertTrue(pixel(image, 10, 10).isClose(to: .red))
        XCTAssertTrue(pixel(image, 75, 25).isClose(to: .green))
        XCTAssertEqual(pixel(image, 56, 6).alpha, 0, "Outside the circle")
        XCTAssertTrue(pixel(image, 25, 75).isClose(to: .blue))
        XCTAssertEqual(pixel(image, 25, 60).alpha, 0, "Outside the ellipse")
        XCTAssertTrue(pixel(image, 80, 80).isClose(to: .black))
    }

    func testRoundedRectCorners() throws {
        let image = try render(#"<rect width="100" height="100" rx="30" fill="red"/>"#)
        XCTAssertEqual(pixel(image, 1, 1).alpha, 0)
        XCTAssertTrue(pixel(image, 50, 1).isClose(to: .red))
    }

    func testLineAndPolylineStroke() throws {
        let image = try render("""
        <line x1="0" y1="10" x2="100" y2="10" stroke="red" stroke-width="6"/>
        <polyline points="0,50 100,50" fill="none" stroke="blue" stroke-width="6"/>
        """)
        XCTAssertTrue(pixel(image, 50, 10).isClose(to: .red))
        XCTAssertTrue(pixel(image, 50, 50).isClose(to: .blue))
        XCTAssertEqual(pixel(image, 50, 30).alpha, 0)
    }

    // MARK: - Paths

    func testPathCommandsAbsoluteAndRelative() throws {
        let image = try render("""
        <path d="M10 10 H40 V40 H10 Z" fill="red"/>
        <path d="m60 10 h30 v30 h-30 z" fill="blue"/>
        <path d="M10,60 C10,60 40,60 40,60 S40,90 40,90 L10,90 Q10,75 10,60 z" fill="black"/>
        """)
        XCTAssertTrue(pixel(image, 25, 25).isClose(to: .red))
        XCTAssertTrue(pixel(image, 75, 25).isClose(to: .blue))
        XCTAssertTrue(pixel(image, 25, 75).isClose(to: .black))
    }

    func testCompactNumbersAndArcs() throws {
        // A half disc drawn with an arc, written with compact numbers and unseparated flags.
        let image = try render(#"<path d="M10 50A40 40 0 0150 10 40 40 0 0190 50z" fill="red"/>"#)
        XCTAssertTrue(pixel(image, 50, 30).isClose(to: .red))
        XCTAssertEqual(pixel(image, 50, 70).alpha, 0)
        XCTAssertEqual(pixel(image, 12, 14).alpha, 0, "Outside the arc")
    }

    func testFillRules() throws {
        let rings = "M10 10 H90 V90 H10 Z M30 30 H70 V70 H30 Z"
        let nonzero = try render(#"<path d="\#(rings)" fill="red"/>"#)
        let evenodd = try render(#"<path d="\#(rings)" fill="red" fill-rule="evenodd"/>"#)
        XCTAssertTrue(pixel(nonzero, 50, 50).isClose(to: .red))
        XCTAssertEqual(pixel(evenodd, 50, 50).alpha, 0)
        XCTAssertTrue(pixel(evenodd, 20, 20).isClose(to: .red))
    }

    // MARK: - Transforms and Viewports

    func testTransforms() throws {
        let image = try render("""
        <rect width="10" height="10" fill="red" transform="translate(50 50) scale(2)"/>
        <rect width="20" height="20" fill="blue" transform="rotate(90 10 10)"/>
        <g transform="matrix(1 0 0 1 0 70)"><rect width="10" height="10" fill="black"/></g>
        """)
        XCTAssertTrue(pixel(image, 65, 65).isClose(to: .red))
        XCTAssertEqual(pixel(image, 45, 45).alpha, 0)
        XCTAssertTrue(pixel(image, 10, 10).isClose(to: .blue))
        XCTAssertTrue(pixel(image, 5, 75).isClose(to: .black))
    }

    func testViewBoxAndPreserveAspectRatio() throws {
        func svg(_ aspect: String) -> String {
            #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" preserveAspectRatio="\#(aspect)"><rect width="10" height="10" fill="red"/></svg>"#
        }
        let meet = try HSVGDocument(data: Data(svg("xMidYMid meet").utf8)).render(pixelSize: CGSize(width: 100, height: 50))
        let slice = try HSVGDocument(data: Data(svg("xMinYMin slice").utf8)).render(pixelSize: CGSize(width: 100, height: 50))
        let none = try HSVGDocument(data: Data(svg("none").utf8)).render(pixelSize: CGSize(width: 100, height: 50))
        XCTAssertEqual(pixel(meet, 5, 25).alpha, 0, "meet letterboxes horizontally")
        XCTAssertTrue(pixel(meet, 50, 25).isClose(to: .red))
        XCTAssertTrue(pixel(slice, 5, 25).isClose(to: .red))
        XCTAssertTrue(pixel(none, 5, 25).isClose(to: .red))
    }

    func testNestedSVGClipsToItsViewport() throws {
        let image = try render(#"<svg x="50" y="0" width="50" height="50" viewBox="0 0 10 10"><rect width="100" height="100" fill="red"/></svg>"#)
        XCTAssertTrue(pixel(image, 75, 25).isClose(to: .red))
        XCTAssertEqual(pixel(image, 75, 75).alpha, 0)
        XCTAssertEqual(pixel(image, 25, 25).alpha, 0)
    }

    // MARK: - Paint

    func testColorsAndOpacity() throws {
        let image = try render("""
        <rect width="20" height="20" fill="rgb(0, 0, 255)"/>
        <rect x="20" width="20" height="20" fill="hsl(120, 100%, 50%)"/>
        <rect x="40" width="20" height="20" fill="#f00" fill-opacity="0.5"/>
        <rect x="60" width="20" height="20" fill="#ff000080"/>
        <rect x="80" width="20" height="20" style="color: blue" fill="currentColor"/>
        """)
        XCTAssertTrue(pixel(image, 10, 10).isClose(to: .blue))
        XCTAssertTrue(pixel(image, 30, 10).isClose(to: .green))
        XCTAssertEqual(pixel(image, 50, 10).alpha, 128, accuracy: 2)
        XCTAssertEqual(pixel(image, 70, 10).alpha, 128, accuracy: 2)
        XCTAssertTrue(pixel(image, 90, 10).isClose(to: .blue))
    }

    func testGroupOpacityCompositesTheGroupAsAWhole() throws {
        // Two overlapping opaque squares at group opacity 0.5: the overlap is 50% too, not 75%.
        let image = try render(#"<g opacity="0.5"><rect width="60" height="60" fill="red"/><rect x="30" y="30" width="60" height="60" fill="red"/></g>"#)
        XCTAssertEqual(pixel(image, 45, 45).alpha, 128, accuracy: 3)
        XCTAssertEqual(pixel(image, 10, 10).alpha, 128, accuracy: 3)
    }

    func testStrokeDashes() throws {
        let image = try render(#"<line x1="0" y1="50" x2="100" y2="50" stroke="red" stroke-width="10" stroke-dasharray="20 20"/>"#)
        XCTAssertTrue(pixel(image, 10, 50).isClose(to: .red))
        XCTAssertEqual(pixel(image, 30, 50).alpha, 0)
        XCTAssertTrue(pixel(image, 50, 50).isClose(to: .red))
    }

    func testInheritanceAndDisplay() throws {
        let image = try render("""
        <g fill="blue"><rect width="50" height="50"/><rect x="50" width="50" height="50" display="none"/></g>
        <g visibility="hidden"><rect y="50" width="50" height="50" fill="red"/></g>
        """)
        XCTAssertTrue(pixel(image, 25, 25).isClose(to: .blue))
        XCTAssertEqual(pixel(image, 75, 25).alpha, 0)
        XCTAssertEqual(pixel(image, 25, 75).alpha, 0)
    }

    // MARK: - Gradients

    func testLinearGradient() throws {
        let image = try render("""
        <defs><linearGradient id="g"><stop offset="0" stop-color="red"/><stop offset="100%" stop-color="blue"/></linearGradient></defs>
        <rect width="100" height="100" fill="url(#g)"/>
        """)
        XCTAssertTrue(pixel(image, 1, 50).isClose(to: .red, tolerance: 12))
        XCTAssertTrue(pixel(image, 98, 50).isClose(to: .blue, tolerance: 12))
    }

    func testRadialGradientUserSpaceAndHrefInheritance() throws {
        let image = try render("""
        <defs>
          <radialGradient id="base"><stop offset="0" stop-color="#00ff00"/><stop offset="1" stop-color="black"/></radialGradient>
          <radialGradient id="g" href="#base" gradientUnits="userSpaceOnUse" cx="50" cy="50" r="50"/>
        </defs>
        <rect width="100" height="100" fill="url(#g)"/>
        """)
        XCTAssertTrue(pixel(image, 50, 50).isClose(to: .green, tolerance: 12))
        XCTAssertTrue(pixel(image, 1, 1).isClose(to: .black, tolerance: 12))
    }

    func testGradientStroke() throws {
        let image = try render("""
        <linearGradient id="g"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="red"/></linearGradient>
        <rect x="20" y="20" width="60" height="60" fill="none" stroke="url(#g)" stroke-width="10"/>
        """)
        XCTAssertTrue(pixel(image, 20, 50).isClose(to: .red))
        XCTAssertEqual(pixel(image, 50, 50).alpha, 0)
    }

    func testMissingPaintServerUsesTheFallback() throws {
        let image = try render(#"<rect width="100" height="100" fill="url(#missing) blue"/>"#)
        XCTAssertTrue(pixel(image, 50, 50).isClose(to: .blue))
    }

    // MARK: - Clipping and Reuse

    func testClipPath() throws {
        let image = try render("""
        <clipPath id="c"><circle cx="50" cy="50" r="25"/></clipPath>
        <rect width="100" height="100" fill="red" clip-path="url(#c)"/>
        """)
        XCTAssertTrue(pixel(image, 50, 50).isClose(to: .red))
        XCTAssertEqual(pixel(image, 5, 5).alpha, 0)
    }

    func testClipPathObjectBoundingBox() throws {
        let image = try render("""
        <clipPath id="c" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath>
        <rect x="20" y="20" width="60" height="60" fill="red" clip-path="url(#c)"/>
        """)
        XCTAssertTrue(pixel(image, 30, 50).isClose(to: .red))
        XCTAssertEqual(pixel(image, 70, 50).alpha, 0)
    }

    func testUseAndSymbol() throws {
        let image = try render("""
        <defs>
          <rect id="square" width="20" height="20"/>
          <symbol id="icon" viewBox="0 0 10 10"><rect width="10" height="10" fill="blue"/></symbol>
        </defs>
        <use href="#square" x="10" y="10" fill="red"/>
        <use xlink:href="#icon" x="50" y="50" width="40" height="40"/>
        """)
        XCTAssertTrue(pixel(image, 20, 20).isClose(to: .red))
        XCTAssertTrue(pixel(image, 70, 70).isClose(to: .blue))
        XCTAssertEqual(pixel(image, 95, 95).alpha, 0)
    }

    func testUseCycleIsRejected() {
        assertThrows(##"<svg xmlns="http://www.w3.org/2000/svg"><g id="a"><use href="#a"/></g></svg>"##) {
            if case .malformed = $0 { return true }
            return false
        }
    }

    // MARK: - CSS

    func testCSSSpecificityAndStyleAttribute() throws {
        let image = try render("""
        <style><![CDATA[
          rect { fill: red; }
          .blue { fill: blue; }
          #green { fill: #00ff00; }
          /* a comment */
        ]]></style>
        <rect width="25" height="100"/>
        <rect x="25" width="25" height="100" class="blue"/>
        <rect x="50" width="25" height="100" class="blue" id="green"/>
        <rect x="75" width="25" height="100" class="blue" style="fill: black" fill="red"/>
        """)
        XCTAssertTrue(pixel(image, 10, 50).isClose(to: .red))
        XCTAssertTrue(pixel(image, 35, 50).isClose(to: .blue))
        XCTAssertTrue(pixel(image, 60, 50).isClose(to: .green))
        XCTAssertTrue(pixel(image, 85, 50).isClose(to: .black))
    }

    func testPresentationAttributesLoseToCSS() throws {
        let image = try render(#"<style>.a { fill: blue }</style><rect class="a" width="100" height="100" fill="red"/>"#)
        XCTAssertTrue(pixel(image, 50, 50).isClose(to: .blue))
    }

    func testIgnoredForeignElements() throws {
        let image = try render(#"<sodipodi:namedview xmlns:sodipodi="x"><rect width="100" height="100" fill="red"/></sodipodi:namedview><title>Icon</title><rect width="10" height="10" fill="blue"/>"#)
        XCTAssertEqual(pixel(image, 50, 50).alpha, 0)
        XCTAssertTrue(pixel(image, 5, 5).isClose(to: .blue))
    }

    // MARK: - Rejections

    func testUnsupportedFeaturesThrow() {
        let cases = [
            "<text>hi</text>",
            #"<image href="a.png" width="10" height="10"/>"#,
            #"<filter id="f"><feGaussianBlur stdDeviation="2"/></filter><rect width="10" height="10" filter="url(#f)"/>"#,
            #"<mask id="m"/><rect width="10" height="10" mask="url(#m)"/>"#,
            #"<rect width="10" height="10"><animate attributeName="x" to="5"/></rect>"#,
            #"<pattern id="p"/><rect width="10" height="10" fill="url(#p)"/>"#,
            #"<path d="M0 0 L10 10" marker-end="url(#m)"/>"#,
            #"<style>g > rect { fill: red }</style><rect width="10" height="10"/>"#,
            #"<style>@media print { rect { fill: red } }</style>"#,
            #"<linearGradient id="g" spreadMethod="reflect"><stop offset="0"/><stop offset="1"/></linearGradient><rect width="10" height="10" fill="url(#g)"/>"#,
        ]
        for body in cases {
            assertThrows(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">\#(body)</svg>"#) {
                if case .unsupported = $0 { return true }
                return false
            }
        }
    }

    func testUnsafeContentThrows() {
        let cases = [
            #"<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"/>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><use href="https://evil.test/a.svg#x"/></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><style>@import url(https://evil.test/a.css);</style></svg>"#,
            #"<!DOCTYPE svg [<!ENTITY ext SYSTEM "file:///etc/passwd">]><svg xmlns="http://www.w3.org/2000/svg">&ext;</svg>"#,
        ]
        for svg in cases {
            assertThrows(svg) {
                if case .unsafe = $0 { return true }
                return false
            }
        }
    }

    func testEntityExpansionBombIsRejected() {
        let bomb = """
        <?xml version="1.0"?>
        <!DOCTYPE svg [
          <!ENTITY a "aaaaaaaaaa">
          <!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">
          <!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">
        ]>
        <svg xmlns="http://www.w3.org/2000/svg"><title>&c;</title></svg>
        """
        assertThrows(bomb) {
            if case .unsafe = $0 { return true }
            return false
        }
    }

    func testSimpleEntitiesAreAccepted() throws {
        let svg = """
        <!DOCTYPE svg [<!ENTITY ns_svg "http://www.w3.org/2000/svg">]>
        <svg xmlns="&ns_svg;" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>
        """
        let image = try HSVGDocument(data: Data(svg.utf8)).render(pixelSize: CGSize(width: 10, height: 10))
        XCTAssertTrue(pixel(image, 5, 5).isClose(to: .red))
    }

    func testMalformedDocumentsThrow() {
        assertThrows("<svg") { if case .malformed = $0 { return true }; return false }
        assertThrows("<html></html>") { if case .malformed = $0 { return true }; return false }
    }

    func testTooLargeRasterThrows() throws {
        let document = try HSVGDocument(data: Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>"#.utf8))
        XCTAssertThrowsError(try document.render(pixelSize: CGSize(width: 20_000, height: 20_000))) { error in
            XCTAssertEqual(error as? HSVGError, .tooLarge)
        }
    }

    func testDeepRenderNestingThrowsInsteadOfOverflowingTheStack() {
        // Groups nested past the render depth (64), within the XML limit (256).
        let groups = #"<svg xmlns="http://www.w3.org/2000/svg">"# + String(repeating: "<g>", count: 100) + "<rect width=\"1\" height=\"1\"/>" + String(repeating: "</g>", count: 100) + "</svg>"
        assertThrows(groups) { $0 == .tooLarge }

        // A chain of `use`, each pointing at a nested group: every hop adds to the depth.
        var defs = ""
        for index in 0..<4 {
            let inner = index == 3 ? #"<rect width="1" height="1"/>"# : ##"<use href="#a\##(index + 1)"/>"##
            defs += #"<g id="a\#(index)">"# + String(repeating: "<g>", count: 30) + inner + String(repeating: "</g>", count: 30) + "</g>"
        }
        let chain = ##"<svg xmlns="http://www.w3.org/2000/svg"><defs>"## + defs + ##"</defs><use href="#a0"/></svg>"##
        assertThrows(chain) { $0 == .tooLarge }
    }

    func testUseMultiplyingAHeavyPathHitsTheWorkBudget() {
        // Given: a 10,000-segment path drawn 300 times
        let path = "M0 0" + String(repeating: " L1 1 L0 0", count: 5_000)
        let uses = String(repeating: ##"<use href="#p"/>"##, count: 300)
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><defs><path id="p" d="\#(path)" stroke="red"/></defs>\#(uses)</svg>"#
        let start = Date()

        // Then: rejected quickly
        assertThrows(svg) { $0 == .tooLarge }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testEntityHiddenAfterACommentIsRejected() {
        let svg = #"<?xml version="1.0"?><!-- <svg --><!DOCTYPE svg [<!ENTITY e SYSTEM "file:///etc/hosts">]><svg xmlns="http://www.w3.org/2000/svg"><title>&e;</title></svg>"#
        assertThrows(svg) {
            if case .unsafe = $0 { return true }
            return false
        }
    }

    func testSemicircleArcUsesTwoCurves() {
        // A 180° arc is drawn with two 90° cubics, not one (which is visibly flattened).
        let path = HSVGPathParser.parse("M0 50 A50 50 0 0 1 100 50")
        XCTAssertEqual(path.segments.filter { if case .cubic = $0 { return true }; return false }.count, 2)
    }

    func testClipPathUnitesShapesThatWindInOppositeDirections() throws {
        let image = try render("""
        <clipPath id="c"><rect width="100" height="100"/><path d="M0 0 V100 H100 V0 Z"/></clipPath>
        <rect width="100" height="100" fill="red" clip-path="url(#c)"/>
        """)
        XCTAssertTrue(pixel(image, 50, 50).isClose(to: .red))
    }

    func testClipPathKeepsEachShapesOwnRule() throws {
        let image = try render("""
        <clipPath id="c"><rect width="100" height="100"/><path d="M20 20 H80 V80 H20 Z M40 40 H60 V60 H40 Z" clip-rule="evenodd"/></clipPath>
        <rect width="100" height="100" fill="red" clip-path="url(#c)"/>
        """)
        XCTAssertTrue(pixel(image, 50, 50).isClose(to: .red), "The full rect covers the even-odd hole")
    }

    func testBoundingBoxClipOnUse() throws {
        let image = try render("""
        <defs><rect id="r" x="20" y="20" width="60" height="60" fill="red"/></defs>
        <clipPath id="c" clipPathUnits="objectBoundingBox"><rect width="1" height="1"/></clipPath>
        <use href="#r" clip-path="url(#c)"/>
        """)
        XCTAssertTrue(pixel(image, 50, 50).isClose(to: .red))
    }

    func testUseOfAnSVGKeepsItsOwnSize() throws {
        let image = try render(##"<svg id="s" width="10" height="10" viewBox="0 0 1 1"><rect width="1" height="1" fill="red"/></svg><use href="#s"/>"##)
        XCTAssertTrue(pixel(image, 5, 5).isClose(to: .red))
        XCTAssertEqual(pixel(image, 50, 50).alpha, 0)
    }

    func testInvalidNumbersAreIgnoredAndRemUnitsResolve() throws {
        let image = try render(#"<rect width="2rem" height="2rem" fill="red" fill-opacity="nan"/>"#)
        XCTAssertTrue(pixel(image, 30, 30).isClose(to: .red), "2rem is 32 user units; a NaN opacity is ignored")
        XCTAssertEqual(pixel(image, 40, 40).alpha, 0)
    }

    func testZeroRadiusRadialGradientPaintsTheLastStop() throws {
        let image = try render("""
        <radialGradient id="g" r="0"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></radialGradient>
        <rect width="100" height="100" fill="url(#g)"/>
        """)
        XCTAssertTrue(pixel(image, 50, 50).isClose(to: .blue))
    }

    func testUnsupportedPaintingPropertiesThrow() {
        for body in [#"<rect width="10" height="10" stroke="red" paint-order="stroke"/>"#,
                     #"<rect width="10" height="10" stroke="red" vector-effect="non-scaling-stroke"/>"#,
                     #"<svg width="5" height="5" overflow="visible"><rect width="10" height="10"/></svg>"#] {
            assertThrows(#"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">\#(body)</svg>"#) {
                if case .unsupported = $0 { return true }
                return false
            }
        }
    }

    func testDeepNestingThrows() {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg">"# + String(repeating: "<g>", count: 300) + String(repeating: "</g>", count: 300) + "</svg>"
        assertThrows(svg) { $0 == .tooLarge }
    }
}
