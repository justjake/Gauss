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
    
    
    var body: some View {
        let nsImages = result.imageIds.map { id in
            return images[id.uuidString]
        }
        NSImageGridView(images: nsImages)
    }
}

struct ResultView_Previews: PreviewProvider {
    @State static var result = GaussResult(promptId: UUID(), imageIds: [UUID()])
    
    static var previews: some View {
        ResultView(result: $result, images: .constant([:]))
    }
}
