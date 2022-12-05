//
//  GenerateImageJobView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/5/22.
//

import SwiftUI

struct GenerateImageJobView: View {
    @ObservedObject job: GenerateImageJob
    
    var body: some View {
        Text("Hello, World!")
    }
}

struct GenerateImageJobView_Previews: PreviewProvider {
    static var previews: some View {
        GenerateImageJobView()
    }
}
