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
        let text = message()
        if text != nil {
            VStack {
                ProgressView {
                    Text(text!)
                }
                .padding()
                .frame(width: 100, height: 100)

            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .aspectRatio(1, contentMode: .fit)
        }
    }
    
    func message() -> String? {
        if !kernel.ready {
            return "Loading model"
        }
        
        if kernel.jobs.count > 1 {
            return "\(kernel.jobs.count) jobs"
        }
        
        if kernel.jobs.count == 1 {
            return "\(kernel.jobs.count) job"
        }

        
        return nil
    }
}

struct KernelStatusView_Previews: PreviewProvider {
    static let kernel = GaussKernel()
    
    static var previews: some View {
        KernelStatusView().environmentObject(kernel).padding()
    }
}
