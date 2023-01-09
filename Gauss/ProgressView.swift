//
//  ProgressView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI
import StableDiffusion

extension Image {
    func square(_ size: CGFloat = 256) -> some View {
        return self.resizable().frame(width: size, height: size)
    }
}

func renderableImageArray(from: [CGImage?]) -> [NSImage] {
    return from.compactMap { maybeImage in
        guard let image = maybeImage else {
            return nil
        }
        
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

struct ImageMessageView<Title: View, Content: View>: View {
    var label: Title
    var content: Content
    
    var body: some View {
        HStack {
            Spacer()
            VStack {
                Spacer()
                Group {
                    self.label
                    self.content
                }
                    .padding()
                    .background(.thinMaterial, in: GaussStyle.rectSmall)
                Spacer()
            }
            Spacer()
        }
    }
}

struct GaussProgressView: View {
    @ObservedObject var job: GenerateImageJob
    
    var nilArray: [NSImage?] {
        return (0..<job.count).map { _ in nil }
    }
    
    var body: some View {
        switch (job.state) {
        case .success(let images):
            NSImageGridView(
                images: images
            )
        case .pending:
            ZStack {
                CustomNSImageGridView(
                    images: nilArray,
                    emptySpace: Spacer(),
                    missingImage: Rectangle().fill(.quaternary)
                )
                
                ImageMessageView(
                    label: ProgressView() {
                        VStack {
                            Button("Cancel") {
                                job.cancel()
                            }
                        }
                    }, content: EmptyView()
                )
            }
            
        case .cancelled:
            CustomNSImageGridView(images: nilArray, emptySpace: Spacer(), missingImage: ErrorImagePlaceholder())
        case .running:
            ZStack {
                let progressOverlay = ProgressDetailOverlay(cancel: job.cancel)
                NSImageGridView(
                    images: nilArray
                ).overlay(progressOverlay, alignment: .bottom)
            }
        case .progress((let images, let progress)):
            ZStack {
                let progressOverlay = ProgressDetailOverlay(step: progress.step, stepCount: progress.stepCount, cancel: job.cancel)
                NSImageGridView(
                    images: images
                ).overlay(progressOverlay, alignment: .bottom)
            }
        case .error(let error):
            ZStack {
                CustomNSImageGridView(images: nilArray, emptySpace: Spacer(), missingImage: ErrorImagePlaceholder())
                
                ImageMessageView(label: Text(error.localizedDescription).foregroundColor(.red), content: EmptyView())
            }
        }
    }
}

struct ProgressDetailOverlay: View {
    var step: Int?
    var stepCount: Int?
    var cancel: () -> Void
    
    var body: some View {
        VStack {
            progressView
            
            Button(action: cancel) {
                Text("Cancel")
            }
        }.padding().background(.thinMaterial)
    }
    
    var progressView: some View {
        let indeterminite = ProgressView().progressViewStyle(.linear)
        guard let step1 = step else {
            return indeterminite
        }
        
        guard let stepCount1 = stepCount else {
            return indeterminite
        }
        
        return ProgressView(
            value: Double(step1),
            total: Double(stepCount1)
        ).progressViewStyle(.linear)
    }
}

struct ProgressView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            GaussProgressView(job: GenerateImageJob(GaussPrompt(), count: 1, execute: {_ in [] }))
                .previewDisplayName("Count: 1")
            
            GaussProgressView(job: GenerateImageJob(GaussPrompt(), count: 3, execute: {_ in [] }))
                .previewDisplayName("Count: 3")
            
            GaussProgressView(job: GenerateImageJob(GaussPrompt(), count: 4, execute: {_ in [] }))
                .previewDisplayName("Count: 4")
            
            GaussProgressView(job: GenerateImageJob(GaussPrompt(), count: 9, execute: {_ in [] }))
                .previewDisplayName("Count: 9")
            
        }
    }
}
