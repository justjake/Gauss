//
//  ImageGridView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/5/22.
//

import QuickLook
import SwiftUI

extension CGImage {
    func asNSImage() -> NSImage {
        return NSImage(cgImage: self, size: NSSize(width: width, height: height))
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
    
    @State var quicklookImage: URL? = nil

    var perRow: Int {
        return Int(round(Double(images.count).squareRoot()))
    }

    var imageURLs: [URL] {
        return images.compactMap {
            try? $0?.temporaryFileURL()
        }
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
                            GridImage(image: image, selected: quicklookImage != nil && quicklookImage == image.maybeTemporaryFileURL)
                            .onTapGesture(count: 2) {
                                quicklookImage = try? image.temporaryFileURL()
                            }.gesture(MagnificationGesture(minimumScaleDelta: 1.2).onChanged { _ in
                                quicklookImage = try? image.temporaryFileURL()
                            }).contextMenu {
                                Button("Copy") {
                                    NSPasteboard.general.setData(image.toPngData(), forType: .png)
                                }
                                Button("Quick Look (double click)") {
                                    quicklookImage = try? image.temporaryFileURL()
                                }
                            }
                        }
                    }
                }
            }
        }.quickLookPreview($quicklookImage, in: imageURLs)
    }
}

struct GridImage: View {
    var image: NSImage
    var selected: Bool = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay(.white.opacity(selected ? 0.2 : 0))
            .onDrag {
                // Built in - provides many representations of image data
                let provider = NSItemProvider(object: image)
                // Custom extension - also provides file URL representation, for Finder
                provider.register(image)
                return provider
            }

        // .draggableAndZoomable()
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
