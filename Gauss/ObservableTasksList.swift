//
//  ObservableTasksList.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 1/9/23.
//

import SwiftUI

struct ObservableTasksList: View {
    @ObservedObject var kernel: GaussKernel = .inst

    var dict: ObservableTaskDictionary {
        kernel.jobs
    }

    var list: [any ObservableTaskProtocol] {
        dict.values.sorted { left, right in
            left.createdAt <= right.createdAt
        }
    }

    var body: some View {
        List(list, id: \.id, children: \.children) { task in
            if task.waiters.count == 0 {
                ObservableTaskView(task: task, observableTask: task.observable)
            }
        }
    }
}

struct ObservableTaskView: View {
    var task: any ObservableTaskProtocol
    @ObservedObject var observableTask: ObservableTaskModel
    @ObservedObject var kernel: GaussKernel = .inst

    var label: some View {
        Text(task.label)
    }

    @ViewBuilder
    var progress: some View {
        if task.anyState.pending {
            ProgressView().progressViewStyle(.linear)
        } else if task.anyState.running {
            ProgressView(task.progress)
        } else {
            Spacer()
        }
    }

    @ViewBuilder
    var action: some View {
        if observableTask.state.pending || observableTask.state.running {
            cancelButton
        } else if observableTask.state.finalized {
            Button("Remove") {
                kernel.jobs.remove(job: task)
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    var cancelButton: some View {
        Button(action: task.cancel) {
            Label("Cancel", systemImage: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .labelStyle(.iconOnly)
                .imageScale(.large)
        }.buttonStyle(.borderless)
    }

    @ViewBuilder
    var details: some View {
        switch task.anyState {
        case .error(let error):
            Text(error.localizedDescription).foregroundColor(.red)
        default:
            EmptyView()
        }
    }

    var body: some View {
        VStack {
            HStack {
                label
                progress
                action
            }
            details
            Divider()
        }
    }
}

struct ObservableJobsList_Previews: PreviewProvider {
    static var previews: some View {
        ObservableTasksList()
    }
}
