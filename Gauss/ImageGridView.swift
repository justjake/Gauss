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

struct CGImageGridView: View {
    var images: [CGImage?]
    
    var nsImages: [NSImage?] {
        return images.map {
            guard let image = $0 else { return nil }
            return image.asNSImage()
        }
    }
    
    var body: some View {
        NSImageGridView(images: nsImages)
    }
}

struct NSImageGridView: View {
    var images: [NSImage?]
    
    var perRow: Int {
        return Int(round(Double(images.count).squareRoot()))
    }
    
    var body: some View {
        let _ = print("render grid with \(images.count) images, \(perRow) per row")
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            ForEach(0..<perRow, id: \.self) { row in
                GridRow {
                    ForEach(0..<perRow, id: \.self) { col in
                        let index = row * perRow + col
                        if index > images.count - 1 {
                            Spacer()
                        } else {
                            MaybeImage(image: images[index])
                        }
                    }
                }
            }
        }.aspectRatio(1, contentMode: .fit)
    }
}

struct MaybeImage: View {
    var image: NSImage?
    
    var body: some View {
        if image == nil {
            VStack {
                Spacer()
                Image(systemName: "hand.raised.fill").resizable().aspectRatio(contentMode: .fit)
                Spacer()
                Text("Unsafe")
                Spacer()
            }.foregroundColor(.yellow).background(.quaternary)
        } else {
            // TODO: click to view?
            Image(nsImage: image!)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}
