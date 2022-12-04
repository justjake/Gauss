//
//  AddPromptButton.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/4/22.
//

import SwiftUI

struct AddPromptButton: View {
    @Binding var document: GaussDocument
    
    var body: some View {
        Button {
            let prompt = GaussPrompt()
            document.prompts.append(prompt)
        } label: {
            Image(systemName: "plus.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(Font.system(size: 24))
                .accessibilityLabel("Add prompt")
        }
        .buttonStyle(.borderless)
        .contentShape(Circle())
    }
}

struct AddPromptButton_Previews: PreviewProvider {
    static var previews: some View {
        AddPromptButton(document: .constant(GaussDocument()))
    }
}
