//
//  GaussKernel.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import Foundation
import SwiftUI
import StableDiffusion
import CoreML

enum GenerateImageState {
    case pending
    case progress(StableDiffusionPipeline.Progress)
    case finished([CGImage?])
    case error(Error)
}



class GenerateImageJob : ObservableObject, Identifiable {
    let id = UUID()
    let prompt: GaussPrompt
    @Published var cancelled = false
    @Published var state: GenerateImageState = .pending

    init(_ prompt: GaussPrompt) {
        self.prompt = prompt
    }
    
    func run() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            
            let url = Bundle.main.resourceURL!
            let pipeline = try StableDiffusionPipeline(
                resourcesAt: url,
                configuration: config
            )
            let sampleTimer = SampleTimer()
            sampleTimer.start()
            let result = try pipeline.generateImages(
                prompt: self.prompt.text,
                imageCount: 1,
                stepCount: Int(self.prompt.steps),
                seed: {
                    switch self.prompt.seed {
                    case .random: return 0
                    case .fixed(let value): return value
                    }
                }(),
                disableSafety: !self.prompt.safety
            ) {
                sampleTimer.stop()
                let progress = $0
                print("Step \(progress.step) / \(progress.stepCount), avg \(sampleTimer.mean) variance \(sampleTimer.variance)")
                if progress.stepCount != progress.step {
                    sampleTimer.start()
                }
                DispatchQueue.main.async {
                    self.state = .progress(progress);
                }
                return self.cancelled
            }
            
            self.state = .finished(result)
        } catch {
            self.state = .error(error)
        }
    }
}

class GaussKernel : ObservableObject {
    @Published var jobs: [UUID : GenerateImageJob] = [:]
    
    func generate(forPrompt: GaussPrompt) -> GenerateImageJob  {
        var job = GenerateImageJob(forPrompt)
        self.jobs[job.id] = job
        DispatchQueue.global(qos: .userInitiated).async {
            job.run()
            DispatchQueue.main.async {
                self.jobs.removeValue(forKey: job.id)
            }
        }
        return job
    }
}
