//
//  SplashView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 1/13/23.
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                Text("Models")
                    .font(.title)
                    .frame(maxWidth: 500, alignment: .leading)
                    .padding(.bottom, 8)
                Text("""
                To generate images with Gauss, we first need to download Stable Diffusion ML models. Each model is about 2.5 GB in size. Once a model is downloaded, no network connection is needed.
                """.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.body)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 500, alignment: .leading)
                    .padding(.bottom, 8)

                AppSettingsView()
            }
        }
    }
}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView()
    }
}
