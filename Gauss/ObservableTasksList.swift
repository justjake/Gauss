//
//  ObservableTasksList.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 1/9/23.
//

import SwiftUI

struct ObservableTasksList: View {
    @ObservedObject var kernel: GaussKernel = .inst
    @State private var updateCount = 0

    var dict: ObservableTaskDictionary {
        kernel.jobs
    }

    var list: [any ObservableTaskProtocol] {
        dict.values.sorted { left, right in
            left.createdAt <= right.createdAt
        }
    }

    var body: some View {
        if list.isEmpty {
            Text("No running tasks").font(.title2).foregroundColor(.gray)
        } else {
            ScrollView {
                Grid {
                    Divider().hidden()
                    ForEach(list, id: \.id) { task in
                        ObservableTaskView(task: task, observableTask: task.observable)
                            .onReceive(task.observable.objectWillChange, perform: { updateCount += 1 })
                    }
                }.gridColumnAlignment(.leading)
            }
        }
    }
}

struct ObservableTaskView: View {
    var task: any ObservableTaskProtocol
    @ObservedObject var observableTask: ObservableTaskModel
    @ObservedObject var kernel: GaussKernel = .inst

    var label: some View {
        Text(task.label).multilineTextAlignment(.leading)
    }
    
    var body: some View {
        GridRow {
            label.padding(.leading).gridColumnAlignment(.leading)
            details
            action.gridColumnAlignment(.trailing).padding(.trailing)
        }
        Divider().padding(.horizontal)
    }

    @ViewBuilder
    var details: some View {
        switch task.anyState {
        case .pending:
            ProgressView().progressViewStyle(.linear)
        case .progress, .running:
            ProgressView(task.progress)
        case .cancelled:
            Text("Cancelled")
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .error(let error):
            Text(error.localizedDescription)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .success:
            Text("Complete")
        }
    }

    @ViewBuilder
    var action: some View {
        if observableTask.state.pending || observableTask.state.running {
            cancelButton(action: task.cancel)
        } else if observableTask.state.finalized {
            cancelButton {
                kernel.jobs.remove(job: task)
            }
        } else {
            cancelButton {
                return
            }.disabled(true).hidden()
        }
    }

    @ViewBuilder
    func cancelButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Cancel", systemImage: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .labelStyle(.iconOnly)
                .imageScale(.large)
        }.buttonStyle(.borderless)
    }

}

struct ObservableJobsList_Previews: PreviewProvider {
    static var privateKernel = {
        var kernel = GaussKernel()
        let tasks: [any ObservableTaskProtocol] = [
            ObservableTask.exampleTask(label: "Imagine 4", errorText: "NN Failed").resume(),
            ObservableTask.exampleTask(label: "Load Stable Diffusion 2.0", errorText: ""),
            ObservableTask.exampleTask(label: "Install Stable Diffusion 1.4", errorText: "Subtask failed").resume(),
            ObservableTask.exampleTask(label: "Download sd1.4.aar.0", errorText: "Could not connect to the server").resume(),
            ObservableTask.exampleTask(label: "Download sd1.4.aar.0", errorText: "Could not connect to the server").resume(),
        ]

        for task in tasks {
            kernel.jobs.insert(job: task)
        }

        return kernel
    }()

    static var previews: some View {
        ObservableTasksList(kernel: privateKernel)
    }
}
