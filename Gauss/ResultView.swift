//
//  ResultView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

extension NSImage: Transferable  {
    static public var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) {
            return $0.toPngData()
        }
    }
}

struct ResultView: View {
    @Binding var result: GaussResult
    @Binding var images: GaussImages
    
    var image: NSImage? {
        return images[result.imageId.uuidString]
    }
    
    var body: some View {
        VStack {
            HStack {
                Text("ImageID: \(result.imageId)")
                Toggle("Favorite", isOn: $result.favorite)

            }
            if (image != nil) {
                Image(nsImage: image!)
                    .fixedSize()
                    .onDrag {
                        let provider = NSItemProvider()
                        provider.register(image!)
                        return provider
                    }
            }
        }

    }
}

struct ResultView_Previews: PreviewProvider {
    @State static var result = GaussResult(promptId: UUID(), imageId: UUID())
    
    static var previews: some View {
        ResultView(result: $result, images: .constant([:]))
    }
}
