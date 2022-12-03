//
//  ProgressView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI

extension Image {
    func square() -> some View {
        return self.resizable().frame(width: 512, height: 512)
    }
}

struct PendingImageView: View {
    var body: some View {
        VStack {
            Text("Pending...")
            Image(systemName: "aqi.medium")
                .square()
        }.foregroundColor(.secondary)
    }
}

struct ImageError: View {
    var message: String
    
    var body: some View {
        VStack {
            Text("Error: \(message)")
            Image(systemName: "exclamationmark.square.fill")
                .square()
                .border(.red)
        }.foregroundColor(.red)
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
        VStack {
            Text("No image data")
            Image(systemName: "questionmark.square.dashed")
                .square()
                .border(.yellow)
        }.foregroundColor(.yellow)
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
                .square()
        } else {
            MissingImage()
        }
        
    }
}

struct ProgressView: View {
    @ObservedObject var job: GenerateImageJob
    
    var body: some View {
        switch (job.state) {
        case .finished(let images):
            FirstCGImageView(images: images)
        case .pending:
            PendingImageView()
        case .progress(let progress):
            ZStack {
                Text("\(progress.step) / \(progress.stepCount)")
                FirstCGImageView(images: progress.currentImages)
            }
        case .error(let error):
            ImageError(message: error.localizedDescription)
        }
    }
}

struct ProgressView_Previews: PreviewProvider {
    static var previews: some View {
        let job = GenerateImageJob(GaussPrompt())
        ProgressView(job: job)
    }
}
