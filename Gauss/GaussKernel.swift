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
    case progress(images: [CGImage], info: StableDiffusionPipeline.Progress)
    case finished([CGImage?])
    case error(Error)
}

class GenerateImageJob : ObservableObject, Identifiable {
    typealias CompletionHandler = ([CGImage?], GenerateImageJob) -> Void
    let id = UUID()
    let count: Int
    let prompt: GaussPrompt
    let completionHandler: CompletionHandler
    @Published var cancelled = false
    @Published var state: GenerateImageState = .pending
    init(_ prompt: GaussPrompt, count: Int, _ completionHandler: @escaping CompletionHandler) {
        self.prompt = prompt
        self.count = count
        self.completionHandler = completionHandler
    }
}

struct GaussKernelResources {
    let sourceCodeRoot = "/Users/jitl/src/gauss/build"
    
    var sourceCodeURL: URL {
        URL(filePath: sourceCodeRoot, directoryHint: .isDirectory)
    }
    
    var sd2production: URL {
        return Bundle.main.url(forResource: "Resources", withExtension: nil)!
    }
    
    func fromSourceCode(modelName: String) -> URL {
        return sourceCodeURL.appending(components: modelName, "Resources")
    }
    
    var sd2Sources: URL {
        return fromSourceCode(modelName: "sd2-base")
    }
    
    var sd14Sources: URL {
        return fromSourceCode(modelName: "sd1.4")
    }
    
    var sd15Sources: URL {
        return fromSourceCode(modelName: "sd1.5")
    }
}

class GaussKernel : ObservableObject {
    @Published var jobs: [UUID : GenerateImageJob] = [:]
    @Published var loadedModels = Set<GaussModel>()
    var ready: Bool {
        return !loadedModels.isEmpty
    }
    
    private let queue = DispatchQueue(label: "Diffusion", qos: .userInitiated)
    private let resources = GaussKernelResources()
    private var pipelines: [GaussModel : StableDiffusionPipeline] = [:]
        
    func preloadPipeline(_ model: GaussModel = GaussModel.Default) {
        if pipelines[model] != nil {
            return
        }
        
        if !jobs.isEmpty {
            print("preloadPipeline: skipping because there are jobs in the queue")
            return
        }
        
        queue.async {
            do {
                let newPipeline = try self.createPipeline(model)
                self.pipelines[model] = newPipeline
                DispatchQueue.main.async {
                    self.loadedModels.insert(model)
                }
            } catch {
                print("Create pipeline error:", error)
            }
        }
    }
    
    private func getOrCreatePipeline(_ model: GaussModel) throws -> StableDiffusionPipeline {
        if let p = self.pipelines[model] {
            print("Using pre-existing pipeline for model \(model)")
            return p
        } else {
            let p = try createPipeline(model)
            pipelines[model] = p
            return p
        }
    }
    
    private func createPipeline(_ model: GaussModel) throws -> StableDiffusionPipeline  {
        print("Create new StableDiffusionPipeline for model \(model)")
        let timer = SampleTimer()
        timer.start()
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
        let url: URL = {
            switch model {
            case .sd2:
                return self.resources.sd2Sources
            case .sd1_4:
                return self.resources.sd14Sources
            case .sd1_5:
                return self.resources.sd15Sources
            case .custom(let url):
                return url
            }
        }()
        
        let pipeline = try StableDiffusionPipeline(
            resourcesAt: url,
            configuration: config
        )
        timer.stop()
        print("Create new StableDiffusionPipeline for model \(model): done after \(timer.median)s")
        return pipeline
    }
    
    func startGenerateImageJob(
        forPrompt: GaussPrompt,
        count: Int,
        completionHandler: @escaping GenerateImageJob.CompletionHandler
    ) -> GenerateImageJob  {
        let job = GenerateImageJob(forPrompt, count: count, completionHandler)
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
            print("Fetching pipeline for job \(job.id)")
            let pipeline: StableDiffusionPipeline = try getOrCreatePipeline(job.prompt.model)
            self.pipelines[job.prompt.model] = pipeline
            
            
            print("Starting pipeline.generateImages")
            let sampleTimer = SampleTimer()
            sampleTimer.start()
            let result = try pipeline.generateImages(
                prompt: job.prompt.text,
                imageCount: job.count,
                stepCount: Int(job.prompt.steps),
                seed: {
                    switch job.prompt.seed {
                    case .random: return Int.random(in: 0...Int(UInt32.max))
                    case .fixed(let value): return value
                    }
                }(),
                disableSafety: !job.prompt.safety,
                guidanceScale: Float(job.prompt.guidance)
            ) {
                sampleTimer.stop()
                
                let progress = $0
                print("Step \(progress.step) / \(progress.stepCount), avg \(sampleTimer.mean) variance \(sampleTimer.variance)")
                let images = progress.currentImages.compactMap { return $0 }
                DispatchQueue.main.async {
                    job.state = .progress(images: images, info: progress)
                }
                
                if progress.stepCount != progress.step {
                    sampleTimer.start()
                }
                
                return !job.cancelled
            }
            
            let nilCount = result.filter { $0 == nil }.count
            let notNilCount = result.count - nilCount
            print("pipeline.generateImages returned \(notNilCount) images and \(nilCount) nils")
            
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
