//
//  ResultView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

struct ResultView: View {
    @Binding var result: GaussResult
    @Binding var images: GaussImages

    var body: some View {
        let nsImages = result.images.map { image in
            images.getImage(ref: image)
        }
        NSImageGridView(
            images: nsImages
        )
        .frame(
            width: GaussStyle.resultSize,
            height: GaussStyle.resultSize
        )
    }
}

struct ResultView_Previews: PreviewProvider {
    @State static var result = GaussResult(promptId: UUID(), images: [GaussImageRef(), GaussImageRef()])

    static var previews: some View {
        ResultView(result: $result, images: .constant([:]))
    }
}
