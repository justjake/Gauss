//
//  KernelStatusView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

extension View {
    public func addBorder<S>(_ content: S, width: CGFloat = 1, cornerRadius: CGFloat) -> some View where S : ShapeStyle {
        let roundedRect = RoundedRectangle(cornerRadius: cornerRadius)
        return clipShape(roundedRect)
             .overlay(roundedRect.strokeBorder(content, lineWidth: width))
    }
}

struct KernelStatusView: View {
    @EnvironmentObject var kernel: GaussKernel
    
    var body: some View {
        if !kernel.ready {
            let rect = RoundedRectangle(cornerRadius: 8, style: .continuous)
            let stroke = rect
                .strokeBorder(.separator)
            let background = rect
                .fill(.background)
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
                
            ProgressView {
                Text("Loading model")
            }.padding()
            .overlay(stroke)
            .background(background)
        }
    }

}

struct KernelStatusView_Previews: PreviewProvider {
    static let kernel = GaussKernel()
    
    static var previews: some View {
        KernelStatusView().environmentObject(kernel).padding()
    }
}
