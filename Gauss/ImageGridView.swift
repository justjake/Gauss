//
//  ImageGridView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/5/22.
//

import SwiftUI

extension CGImage {
    func asNSImage() -> NSImage {
        return NSImage(cgImage: self, size: NSSize(width: self.width, height: self.height))
    }
}

struct NSImageGridView: View {
    var images: [NSImage?]
    
    var body: some View {
        CustomNSImageGridView(images: images, emptySpace: Spacer(), missingImage: MissingImagePlaceholder())
    }
}

struct CustomNSImageGridView<Empty: View, Missing: View>: View {
    var images: [NSImage?]
    var emptySpace: Empty
    var missingImage: Missing
    
    var perRow: Int {
        return Int(round(Double(images.count).squareRoot()))
    }
    
    var body: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            ForEach(0..<perRow, id: \.self) { row in
                GridRow {
                    ForEach(0..<perRow, id: \.self) { col in
                        let index = row * perRow + col
                        if index > images.count - 1 {
                            emptySpace
                        } else if images[index] == nil {
                            missingImage
                        } else {
                            let image = images[index]!
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .onDrag {
                                    let provider = NSItemProvider(object: image)
                                    provider.register(image)
//                                    provider.register(image)
                                    print("Drag started")
                                    print("Data types:", provider.registeredContentTypes(conformingTo: .data))
                                    print("Image types:", provider.registeredContentTypes(conformingTo: .image))
                                    print("URL types:", provider.registeredContentTypes(conformingTo: .url))
                                    return provider
                                }
                        }
                    }
                }
            }
        }
    }
}

struct ImagePlaceholderView<Content: View>: View {
    var placeholder: Image
    var content: Content
    
    var body: some View {
        HStack {
            Spacer()
            VStack {
                Spacer()
                placeholder
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: .resultIconSize)
                content
                Spacer()
            }
            Spacer()
        }.foregroundColor(.secondary).background(.quaternary)
    }
}

struct MissingImagePlaceholder: View {
    var body: some View {
        ImagePlaceholderView(
            placeholder: Image(systemName: "questionmark.square.fill"),
            content: Text("Missing Image")
        ).help("Missing image may have been unsafe")
    }
}

struct ErrorImagePlaceholder: View {
    var body: some View {
        ImagePlaceholderView(
            placeholder: Image(systemName: "xmark.square.fill"),
            content: EmptyView()
        )
    }
}


struct ImageGridView_Previews: PreviewProvider {
    static var previews: some View {
        NSImageGridView(images: [nil, nil, nil]).previewDisplayName("3")
        
        MissingImagePlaceholder().previewDisplayName("1")
    }
}
