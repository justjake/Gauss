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
    typealias CompletionHandler = ([CGImage?], GenerateImageJob) -> Void
    let id = UUID()
    let prompt: GaussPrompt
    let completionHandler: CompletionHandler
    @Published var cancelled = false
    @Published var state: GenerateImageState = .pending
    init(_ prompt: GaussPrompt, _ completionHandler: @escaping CompletionHandler) {
        self.prompt = prompt
        self.completionHandler = completionHandler
    }
}

class GaussKernel : ObservableObject {
    @Published var jobs: [UUID : GenerateImageJob] = [:]
    @Published var ready = false
    
    private var pipeline: StableDiffusionPipeline?
    private let queue = DispatchQueue(label: "Diffusion", qos: .userInitiated)
        
    func preloadPipeline() {
        if self.pipeline != nil {
            return
        }
        
        queue.async {
            do {
                let newPipeline = try self.createPipeline()
                DispatchQueue.main.async {
                    self.pipeline = newPipeline
                    self.ready = true
                }
            } catch {
                print("Create pipeline error:", error)
            }
        }
    }
    
    private func createPipeline() throws -> StableDiffusionPipeline  {
        print("Create new StableDiffusionPipeline")
        let timer = SampleTimer()
        let url = Bundle.main.url(forResource: "Resources", withExtension: nil)!
        timer.start()
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        let pipeline = try StableDiffusionPipeline(
            resourcesAt: url,
            configuration: config
        )
        timer.stop()
        print("Create new StableDiffusionPipeline: done after \(timer.median)s")
        return pipeline
    }
    
    func startGenerateImageJob(
        forPrompt: GaussPrompt,
        completionHandler: @escaping GenerateImageJob.CompletionHandler
    ) -> GenerateImageJob  {
        let job = GenerateImageJob(forPrompt, completionHandler)
        self.jobs[job.id] = job
        print("About to enqueue work")
        queue.async {
            self.performGenerateImageJob(job)
        }
        print("returned from .generate")
        return job
    }
    
    private func performGenerateImageJob(_ job: GenerateImageJob) {
        do {
            let pipeline: StableDiffusionPipeline = try {
                print("Fetching pipeline for job")
                if let p = self.pipeline {
                    print("Using pre-existing pipeline")
                    return p
                } else {
                    print("Creating new pipeline")
                    return try createPipeline()
                }
            }()
            
            let sampleTimer = SampleTimer()
            
            print("Starting pipeline.generateImages")
            sampleTimer.start()
            let result = try pipeline.generateImages(
                prompt: job.prompt.text,
                imageCount: 1,
                stepCount: Int(job.prompt.steps),
                seed: {
                    switch job.prompt.seed {
                    case .random: return 0
                    case .fixed(let value): return value
                    }
                }(),
                disableSafety: !job.prompt.safety
            ) {
                sampleTimer.stop()
                
                let progress = $0
                print("Step \(progress.step) / \(progress.stepCount), avg \(sampleTimer.mean) variance \(sampleTimer.variance)")
                
                if progress.stepCount != progress.step {
                    sampleTimer.start()
                }
                
                return job.cancelled
            }
            
            DispatchQueue.main.async {
                job.state = .finished(result)
                job.completionHandler(result, job)
            }

            
            
        } catch {
            print("job error:", error)
            DispatchQueue.main.async {
                job.state = .error(error)
            }
        }
    }
}
