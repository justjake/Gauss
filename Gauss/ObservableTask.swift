//
//  JobQueue.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/11/22.
//

import Foundation
import SwiftUI

enum ObservableTaskState<P, R> {
    case pending
    case running
    case progress(P)
    case success(R)
    case error(Error)
    case cancelled(reason: String)
    
    var erased: ObservableTaskState<Any, Any> {
        switch self {
        case .pending: return .pending
        case .running: return .running
        case .progress(let progress): return .progress(progress)
        case .cancelled(let reason): return .cancelled(reason: reason)
        case .error(let error): return .error(error)
        case .success(let result): return .success(result)
        }
    }
    
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
    
    var running: Bool {
        switch self {
        case .running: return true
        case .progress: return true
        default: return false
        }
    }
    
    var pending: Bool {
        switch self {
        case .pending: return true
        default: return false
        }
    }
    
    var finalized: Bool {
        switch self {
        case .error: return true
        case .success: return true
        case .cancelled: return true
        default: return false
        }
    }
}

extension ObservableTaskState<Any, Any> {
    func cast<Success, OwnProgress>(success: Success.Type, progress: OwnProgress.Type) -> ObservableTaskState<OwnProgress, Success> {
        switch self {
        case .progress(let value):
            return .progress(value as! OwnProgress)
        case .success(let value):
            return .success(value as! Success)
        case .error(let value):
            return .error(value)
        case .running:
            return .running
        case .pending:
            return .pending
        case .cancelled(reason: let reason):
            return .cancelled(reason: reason)
        }
    }
}

typealias ObservableTaskDictionary = [UUID: any ObservableTaskProtocol]

extension ObservableTaskDictionary {
    mutating func insert(job: any ObservableTaskProtocol) {
        self[job.id] = job
    }
    
    mutating func remove(job: any ObservableTaskProtocol) {
        removeValue(forKey: job.id)
    }
        
    @MainActor
    var pending: [UUID: any ObservableTaskProtocol] {
        self.filter { _, v in v.anyState.pending }
    }
    
    @MainActor
    var running: [UUID: any ObservableTaskProtocol] {
        self.filter { _, v in v.anyState.running }
    }
    
    @MainActor
    var finalized: [UUID: any ObservableTaskProtocol] {
        self.filter { _, v in v.anyState.finalized }
    }

    func ofType<T: ObservableTaskProtocol>(_ type: T.Type) -> [UUID: T] {
        compactMapValues { v in v as? T }
    }
}

enum QueueJobError: Error, LocalizedError {
    case invalidState(String)
    case modelNotFound(GaussModel)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound(let model):
            return "Model \"\(model.description)\" not installed"
        case .invalidState(let message):
            return message
        }
    }
}

/// a Task that can be manually fulfilled with a result by external code.
class FulfillableTask<Success: Sendable> {
    typealias Failure = any Error
    typealias Continuation = CheckedContinuation<Result<Success, Failure>, Never>
    
    actor Waiter {
        var pending = [Continuation]()
        var result: Result<Success, Failure>?
        
        @discardableResult
        func fulfill(result: Result<Success, Failure>) -> Bool {
            guard self.result == nil else {
//                print("Waiter: already fulfilled:", self.result as Any, "discarded:", result)
                return false
            }
            
//            print("Waiter: fulfilled for first time", self)
            self.result = result
            
            for cont in pending {
                cont.resume(returning: result)
            }
            pending.removeAll()
            return true
        }
        
        func addContinuation(_ continuation: Continuation) {
            if let result = result {
//                print("Waiter: addContinuation: already resolved, resuming...")
                continuation.resume(returning: result)
            } else {
//                print("Waiter: append continuation")
                pending.append(continuation)
            }
        }
    }
    
    public let waiter = Waiter()
    
    public lazy var task: Task<Success, Failure> = {
        let waiter = self.waiter
        return Task {
            let result = await withCheckedContinuation { continuation in
                Task {
                    await waiter.addContinuation(continuation)
//                    print("FulfillableTask: added continuation")
                }
            }
//            print("FulfillableTask: resolving")
            return try result.get()
        }
    }()
    
    public func resolve(_ success: Success) {
        fulfill(result: .success(success))
    }
    
    public func reject(_ failure: Failure) {
        fulfill(result: .failure(failure))
    }
    
    public func fulfill(result: Result<Success, Failure>) {
        let waiter = self.waiter
        Task { await waiter.fulfill(result: result) }
    }
}

protocol Waitable {
    func wait() async
}

extension Task: Waitable {
    func wait() async {
        _ = await result
    }
}

extension DeferredTask: Waitable {
    func wait() async {
        await task.wait()
    }
}

extension FulfillableTask: Waitable {
    func wait() async {
        await task.wait()
    }
}

/// An async Task that only starts to execute once `resume` is called.
/// Callers may wait for the task indefinitely via `deferred.task.value`.
struct DeferredTask<Success: Sendable> {
    public let operation: () async throws -> Success
    
    private var fulfillable = FulfillableTask<Success>()
    private var internalTask: Task<Void, Never>?
    
    public var task: Task<Success, Error> {
        return fulfillable.task
    }
    
    init(operation: @escaping () async throws -> Success) {
        self.operation = operation
    }
    
    public mutating func resume() {
        guard internalTask == nil else {
            return
        }
        
        guard !task.isCancelled else {
            return
        }
        
        let operation = operation
        let fulfillable = fulfillable
        internalTask = Task {
            do {
                await fulfillable.waiter.fulfill(result: .success(try await operation()))
            } catch {
                await fulfillable.waiter.fulfill(result: .failure(error))
            }
        }
    }
    
    public mutating func cancel() {
        internalTask?.cancel()
        task.cancel()
    }
}

/// Ensure that only a single enqueued task is running at a time.
/// The intention is to mimic the semantics of DispatchQueue with Swift Concurrency.
actor AsyncQueue {
    var queue = [any ObservableTaskProtocol]()
    var current: (any ObservableTaskProtocol)?
    
    func enqueue(_ task: any ObservableTaskProtocol) {
        queue.append(task)
        next()
    }
            
    private func next() {
        if current != nil {
            return
        }
        
        if queue.isEmpty {
            return
        }
        
        let job = queue.removeFirst()
        current = job
        Task {
            job.resume()
            await job.wait()
            current = nil
            next()
        }
    }
}

protocol ObservableTaskProtocol: Identifiable, ProgressReporting {
    associatedtype Success
    associatedtype SpecialProgress
    
    var id: UUID { get }
    var createdAt: Date { get }
    var label: String { get }

    var observable: ObservableTaskModel { get }
    @MainActor var state: ObservableTaskState<SpecialProgress, Success> { get }
    @MainActor var waitingFor: ObservableTaskDictionary { get }
    @MainActor var waiters: Set<UUID> { get }
    var task: Task<Success, Error> { get }
    
    @discardableResult func resume() -> Self
    func didStartWaiting(waiter: any ObservableTaskProtocol) async
    func didFinishWaiting(waiter: any ObservableTaskProtocol) async
    func wait() async
    func waitSuccess() async throws
    func cancel()
}

extension ObservableTaskProtocol {
    @MainActor var anyState: ObservableTaskState<Any, Any> {
        state.erased
    }
    
    @MainActor var children: [any ObservableTaskProtocol]? {
        if waitingFor.values.isEmpty {
            return nil
        } else {
            return Array(waitingFor.values)
        }
    }
}

/// Stores all the published elements of an ObservableTask in a type-erased way, eg as `Any`.
/// We do so to avoid an annoying issue where a `any SomeProtocol` can't be used as an `@ObservedObject`,
/// and we can't upcast a `GenericClass<T>` to `GenericClass<Any>`.
///
/// The hoops we're jumping thorugh are:
/// 1. An action like `startGeneratingImage()` creates a subclass of ObservableTask with custom success and progress types
/// 2. We put that task into a dictionary of all jobs
/// 3. We get all the active jobs
/// 4. We loop over the jobs and render a view for each one. This view should be able to subscribe to the job via @ObservedObject
class ObservableTaskModel: ObservableObject, Identifiable {
    let id: UUID
    @MainActor @Published var state: ObservableTaskState<Any, Any> = .pending
    @MainActor @Published var waitingFor = ObservableTaskDictionary()
    @MainActor @Published var waiters = Set<UUID>()
    
    init(id: UUID) {
        self.id = id
    }
}

/// An ObservableTask is a Task-like abstraction that reports its progress via a published property on the main thread.
/// ObservableTasks are deferred; they begin executing once `observableTask.resume()` is called.
// TODO: https://developer.apple.com/documentation/foundation/progress#1661050
class ObservableTask<Success: Sendable, OwnProgress: Sendable>: NSObject, Identifiable, ProgressReporting, ObservableTaskProtocol {
    typealias Perform = (ObservableTask<Success, OwnProgress>) async throws -> Success

    let id = UUID()
    let createdAt = Date.now
    let label: String
    let fn: Perform
    var progress = Progress()
    
    // Proxy observable tstate to ObservableTaskModel
    let observable: ObservableTaskModel
    @MainActor var anyState: ObservableTaskState<Any, Any> {
        return observable.state
    }
    
    @MainActor var state: ObservableTaskState<OwnProgress, Success> {
        return observable.state.cast(success: Success.self, progress: OwnProgress.self)
    }
    
    @MainActor var waitingFor: ObservableTaskDictionary {
        return observable.waitingFor
    }
    
    @MainActor var waiters: Set<UUID> {
        return observable.waiters
    }
    
    init(_ label: String, _ fn: @escaping Perform) {
        self.label = label
        self.fn = fn
        self.observable = ObservableTaskModel(id: id)
    }
    
    lazy var deferred: DeferredTask<Success> = DeferredTask {
        let currentState = await self.state
        guard case .pending = currentState else {
            throw QueueJobError.invalidState("Expected pending job, but was \(currentState)")
        }

        do {
            await MainActor.run { self.observable.state = .running }
            let result = try await self.work()
            self.progress.completedUnitCount = self.progress.totalUnitCount
            await MainActor.run { self.observable.state = .success(result) }
            return result
        } catch {
            await MainActor.run { self.observable.state = .error(error) }
            throw error
        }
    }
    
    var task: Task<Success, Error> {
        return deferred.task
    }
    
    @discardableResult
    func resume() -> Self {
        deferred.resume()
        return self
    }
    
    func work() async throws -> Success {
        return try await fn(self)
    }
        
    func reportProgress(_ progress: OwnProgress) async {
        await MainActor.run {
            if self.state.running {
                self.observable.state = .progress(progress)
            }
        }
    }
    
    func dependOn(_ other: any ObservableTaskProtocol) async {
        await MainActor.run {
            observable.waitingFor.insert(job: other)
        }
        await other.didStartWaiting(waiter: self)
//        progress.totalUnitCount += 1
        // TODO: figure out how we want to do tracking
        //        progress.addChild(other.progress, withPendingUnitCount: 1)
    }
    
    func waitForValue<Success: Sendable, Progress: Sendable>(_ other: ObservableTask<Success, Progress>) async throws -> Success {
        try await waitFor(other)
        return try await other.task.result.get()
    }
    
    func waitFor(_ other: any ObservableTaskProtocol) async throws {
        await dependOn(other)
        await other.wait()
        await MainActor.run { observable.waitingFor.remove(job: other) }
        await other.didFinishWaiting(waiter: self)
        try await other.waitSuccess()
    }
    
    func didStartWaiting(waiter: any ObservableTaskProtocol) async {
        _ = await MainActor.run { observable.waiters.insert(waiter.id) }
    }
    
    func didFinishWaiting(waiter: any ObservableTaskProtocol) async {
        _ = await MainActor.run { observable.waiters.remove(waiter.id) }
    }
    
    func cancel(reason: String) {
        progress.cancel()
        deferred.cancel()
        Task {
            await MainActor.run { observable.state = .cancelled(reason: reason) }
        }
    }
    
    func cancel() {
        cancel(reason: "Unknown")
    }
    
    func onSuccess(_ handler: @escaping (Success) -> Void) -> Self {
        onSettled { result in
            if case .success(let success) = result {
                handler(success)
            }
        }
    }
    
    func onFailure(_ handler: @escaping (Error) -> Void) -> Self {
        onSettled { result in
            if case .failure(let error) = result {
                handler(error)
            }
        }
    }
    
    func onSettled(_ handler: @escaping (Result<Success, Error>) -> Void) -> Self {
        Task {
            let result = await task.result
            await MainActor.run { handler(result) }
        }
        return self
    }
    
    func wait() async {
        _ = await task.result
    }
    
    func waitSuccess() async throws {
        _ = try await task.value
    }
}
