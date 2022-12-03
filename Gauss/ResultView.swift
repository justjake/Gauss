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
        Text("ImageID: \(result.imageId)")
        Toggle("Favorite", isOn: $result.favorite)
    }
}

struct ResultView_Previews: PreviewProvider {
    @State static var result = GaussResult(promptId: UUID(), imageId: UUID())
    
    static var previews: some View {
        ResultView(result: $result, images: .constant([:]))
    }
}
