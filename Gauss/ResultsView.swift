//
//  ResultsView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/5/22.
//

import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var kernel: GaussKernel
    @Binding var prompt: GaussPrompt
    @Binding var images: GaussImages
    var jobs: [GenerateImageJob] {
        return kernel.getJobs(for: prompt)
    }

    var hasResults: Bool {
        return jobs.count > 0 || prompt.results.count > 0
    }

    var body: some View {
        if hasResults {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 1) {
                    PersistedResultsView(
                        prompt: prompt, results: $prompt.results, images: $images
                    )

                    PendingResultsView(
                        prompt: prompt, jobs: jobs
                    )
                }
            }
        }
    }
}

// Keep getting IndexOutOfBounds panics
// Internet suggests MORE VIEWS
struct PersistedResultsView: View {
    var prompt: GaussPrompt
    @Binding var results: [GaussResult]
    @Binding var images: GaussImages

    var body: some View {
        ForEach($results) { $result in
            ResultView(result: $result, images: $images)
                .id(result.id)
                .aspectRatio(CGSize(width: prompt.width, height: prompt.height), contentMode: .fit)
                .frame(height: .resultSize)
        }
    }
}

struct PendingResultsView: View {
    var prompt: GaussPrompt
    var jobs: [GenerateImageJob]
    var body: some View {
        ForEach(jobs) { job in
            GaussProgressView(job: job)
                .id(job.id)
                .aspectRatio(CGSize(width: prompt.width, height: prompt.height), contentMode: .fit)
                .frame(height: .resultSize)
        }
    }
}

struct ResultsView_Previews: PreviewProvider {
    static var previews: some View {
        let result = { GaussResult(promptId: UUID(), images: [GaussImageRef()]) }
        let prompt = GaussPrompt(results: [result(), result()])
        ResultsView(
            prompt: .constant(prompt), images: .constant(GaussImages())
        )
    }
}
