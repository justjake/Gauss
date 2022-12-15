//
//  KernelStatusView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import StableDiffusion
import SwiftUI

public extension View {
    func addBorder<S>(_ content: S, width: CGFloat = 1, cornerRadius: CGFloat) -> some View where S: ShapeStyle {
        let roundedRect = RoundedRectangle(cornerRadius: cornerRadius)
        return clipShape(roundedRect)
            .overlay(roundedRect.strokeBorder(content, lineWidth: width))
    }
}

struct KernelStatusView: View {
    @EnvironmentObject var kernel: GaussKernel

    var body: some View {
        let activeJobs: [any ObservableTaskProtocol] = Array(kernel.jobs.pending.merging(kernel.jobs.running) { left, _ in left }.values)
        if !activeJobs.isEmpty {
            VStack {
                ForEach(activeJobs, id: \.id) { job in
                    switch job {
                    case let job as GenerateImageJob:
                        KernelStatusRow(job: job)
                    case let job as PreloadModelJob:
                        KernelStatusRow(job: job)
                    case let job as LoadModelJob:
                        KernelStatusRow(job: job)
                    default:
                        EmptyView()
                    }
                }
            }.padding()
            .frame(width: 300)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }

    }
}

struct KernelStatusRow<Job: ObservableTaskProtocol>: View {
    @ObservedObject var job: Job

    var body: some View {
        HStack(spacing: 15) {
            Text(job.label).multilineTextAlignment(.leading)
            
            Spacer()

            switch job.anyState {
            case .error(let error):
                Text(error.localizedDescription).foregroundColor(.red)
            case .pending:
                ProgressView()
                cancelButton
            case .running:
                ProgressView()
                cancelButton
            case .progress(let inner):
                if let imageProgress = inner as? ([NSImage?], StableDiffusionPipeline.Progress) {
                    ProgressView(value: Double(imageProgress.1.step), total: Double(imageProgress.1.stepCount))
                } else {
                    ProgressView()
                }
                cancelButton
            case .complete:
                EmptyView()
            case .cancelled:
                EmptyView()
            }
        }
    }
    
    var cancelButton: some View {
        Button(action: job.cancel) {
            Label("Cancel", systemImage: "xmark.circle.fill").symbolRenderingMode(.hierarchical)
        }
    }
}

struct KernelStatusView_Previews: PreviewProvider {
    static let kernel = GaussKernel()

    static var previews: some View {
        KernelStatusView().environmentObject(kernel).padding()
    }
}
