//
//  MediaGroup.swift
//  HarborExample
//
//  HarborImage
//

import SwiftUI

struct MediaGroup: View {
    var body: some View {
        ExampleGroup(title: "Images", subtitle: "Loading, processing and caching with HarborImage.") {
            ExampleSection(title: "Images (HarborImage)") {
                ExampleLink(title: "Open the Images demo", icon: "photo.on.rectangle.angled") {
                    ImagesView()
                }
            }
        }
    }
}
