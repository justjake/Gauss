//
//  ProgressView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

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
        VStack {
            Spacer()
            self.label
            Spacer()
            self.content
            Spacer()
        }
        .frame(width: 512, height: 512)
        .cornerRadius(3)
    }
}

struct PendingImageView: View {
    var body: some View {
        ImageMessageView(
            label: Text("Waiting to generate"),
            content: ProgressView()
                .frame(width: 256, height: 256)
        ).foregroundColor(.secondary)
    }
}

struct ImageError: View {
    var message: String
    
    var body: some View {
        ImageMessageView(
            label: Text("Error: \(message)"),
            content: Image(systemName: "exclamationmark.square.fill").square()
        ).foregroundColor(.red)
            .border(.red)
    }
}

struct FirstCGImageView: View {
    var images: [CGImage?]
    
    var body: some View {
        if images.isEmpty {
            ImageError(message: "No images produced")
        } else {
            CGImageView(cgimage: images[0])
        }
    }
}

struct MissingImage: View {
    var body: some View {
        ImageMessageView(
            label: Text("No image data"),
            content: Image(systemName: "questionmark.square.dashed").square()
        ).foregroundColor(.yellow)
            .border(.yellow)
    }
}

struct CGImageView: View {
    var cgimage: CGImage?
    
    var body: some View {
        if cgimage != nil {
            let nsImage = NSImage(
                cgImage: cgimage!,
                size: NSSize(width: 512, height: 512)
            )
            
            Image(nsImage: nsImage)
                .square(512)
                .onDrag {
                    let provider = NSItemProvider()
                    provider.register(nsImage)
                    return provider
                }
        } else {
            MissingImage()
        }
        
    }
}

struct GaussProgressView: View {
    @ObservedObject var job: GenerateImageJob
    
    var body: some View {
        switch (job.state) {
        case .finished(let images):
            FirstCGImageView(images: images)
        case .pending:
            ZStack {
                PendingImageView()
                Button("Cancel") {
                    job.cancel()
                }
            }

        case .progress(let images, let progress):
            ZStack {
                CGImageGridView(images: images)
                VStack {
                    Text("\(progress.step) / \(progress.stepCount)")
                    Button("Cancel") {
                        job.cancel()
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        case .error(let error):
            ImageError(message: error.localizedDescription)
        }
    }
}

struct ProgressView_Previews: PreviewProvider {
    static var previews: some View {
        let job = GenerateImageJob(GaussPrompt(), count: 1, {_,_ in })
        
        Group {
            CGImageView(cgimage: nil)
                .previewDisplayName("Missing image")
            
            FirstCGImageView(images: [])
                .previewDisplayName("Empty image array")
            
            ImageError(message: "Unknown error occured")
                .previewDisplayName("Error")
            
            GaussProgressView(job: job)
                .previewDisplayName("Pending job")
            
        }
    }
}
