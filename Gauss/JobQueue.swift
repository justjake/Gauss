//
//  JobQueue.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/11/22.
//

import Foundation
import SwiftUI

enum QueueJobState<P, R> {
    case pending
    case running
    case progress(P)
    case complete(R)
    case error(Error)
    case cancelled(reason: String)
    
    var erased: QueueJobState<Any, Any> {
        switch self {
        case .pending: return .pending
        case .running: return .running
        case .progress(let progress): return .progress(progress)
        case .cancelled(let reason): return .cancelled(reason: reason)
        case .error(let error): return .error(error)
        case .complete(let result): return .complete(result)
        }
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
        case .complete: return true
        case .cancelled: return true
        default: return false
        }
    }
}

@MainActor
class ObservableTaskTracker: ObservableObject {
    @Published var jobs: [UUID: any ObservableTaskProtocol] = [:]
        
    func insert(job: any ObservableTaskProtocol) {
        jobs[job.id] = job
    }
    
    func remove(job: any ObservableTaskProtocol) {
        jobs.removeValue(forKey: job.id)
    }
        
    var pending: [UUID: any ObservableTaskProtocol] {
        self.jobs.filter { _, v in v.anyState.pending }
    }
    
    var running: [UUID: any ObservableTaskProtocol] {
        self.jobs.filter { _, v in v.anyState.running }
    }
    
    var finalized: [UUID: any ObservableTaskProtocol] {
        self.jobs.filter { _, v in v.anyState.finalized }
    }
}

typealias ObservableTaskDictionary = [UUID: any ObservableTaskProtocol]

extension ObservableTaskDictionary {
    mutating func insert(job: any ObservableTaskProtocol) {
        self[job.id] = job
    }
    
    mutating func remove(job: any ObservableTaskProtocol) {
        self.removeValue(forKey: job.id)
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
        self.compactMapValues { v in v as? T }
    }
}

class JobQueue: ObservableObject {
    @Published var jobs: [UUID: any QueueJobProtocol] = [:]
    let dispatchQueue: DispatchQueue
    
    init(label: String) {
        dispatchQueue = DispatchQueue(label: label, qos: .userInitiated)
    }
    
    func insert(job: any QueueJobProtocol) {
        job.queue = self
        jobs[job.id] = job
    }
    
    func remove(job: any QueueJobProtocol) {
        jobs.removeValue(forKey: job.id)
        job.queue = nil
    }
    
    func async<P, R>(job: QueueJob<P, R>, completionHandler: @escaping (QueueJob<P, R>) -> Void) {
        insert(job: job)
        dispatchQueue.async {
            job.work { _ in
                if case .complete = job.state {
                    self.remove(job: job)
                }
                completionHandler(job)
            }
        }
    }
    
    var pending: [UUID: any QueueJobProtocol] {
        self.jobs.filter { _, v in v.pending }
    }
    
    var running: [UUID: any QueueJobProtocol] {
        self.jobs.filter { _, v in v.running }
    }
    
    var finalized: [UUID: any QueueJobProtocol] {
        self.jobs.filter { _, v in v.finalized }
    }
}

enum QueueJobError: Error {
    case invalidState(String)
    case dependencyCancelled(String)
}

protocol QueueJobProtocol: Identifiable, ObservableObject {
    var id: UUID { get }
    var queue: JobQueue? { get set }
    var label: String { get }
    var dependsOn: Set<UUID> { get }
    var anyState: QueueJobState<Any, Any> {
        get
    }
}

extension QueueJobProtocol {
    var pending: Bool {
        return !running && !finalized
    }
    
    var running: Bool {
        switch anyState {
        case .progress: return true
        case .running: return true
        default: return false
        }
    }
    
    var finalized: Bool {
        switch anyState {
        case .cancelled: fallthrough
        case .error: fallthrough
        case .complete: return true
        case .pending: return false
        case .running: return false
        case .progress: return false
        }
    }
    
    var cancelled: Bool {
        switch anyState {
        case .cancelled: return true
        default: return false
        }
    }
}

var tokens = [UUID: CheckedContinuation<Never, Never>]()

class FulfillableTask<Success: Sendable> {
    typealias Failure = any Error
    typealias Continuation = CheckedContinuation<Result<Success, Failure>, Never>
    
    actor Waiter {
        var pending = [Continuation]()
        var result: Result<Success, Failure>?
        
        @discardableResult
        func fulfill(result: Result<Success, Failure>) -> Bool {
            guard self.result == nil else {
                return false
            }
            
            self.result = result
            
            for cont in pending {
                cont.resume(returning: result)
            }
            pending.removeAll()
            return true
        }
        
        func addContinuation(_ waiter: Continuation) {
            if let result = result {
                waiter.resume(returning: result)
            } else {
                pending.append(waiter)
            }
        }
    }
    
    public let waiter = Waiter()
    
    public lazy var task: Task<Success, Failure> = {
        let waiter = self.waiter
        return Task {
            let result = await withCheckedContinuation { continuation in
                Task { await waiter.addContinuation(continuation) }
            }
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
        _ = await self.result
    }
}

extension DeferredTask: Waitable {
    func wait() async {
        await self.task.wait()
    }
}

extension FulfillableTask: Waitable {
    func wait() async {
        await self.task.wait()
    }
}

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

actor Protected<T> {
    var value: T
    
    init(value: T) {
        self.value = value
    }
    
    func use<R: Sendable>(_ fn: () async throws -> R) async rethrows -> R {
        return try await fn()
    }
}

protocol ObservableTaskProtocol: ObservableObject, Identifiable {
    var id: UUID { get }
    var label: String { get }
    @MainActor var anyState: QueueJobState<Any, Any> { get }
    @discardableResult func resume() -> Self
    func wait() async
    func cancel()
}

extension ObservableTask: ObservableTaskProtocol {
    @MainActor var anyState: QueueJobState<Any, Any> {
        return state.erased
    }

    func wait() async {
        _ = await task.result
    }
}

class ObservableTask<Success: Sendable, Progress: Sendable>: ObservableObject, Identifiable {
    typealias Perform = (ObservableTask<Success, Progress>) async throws -> Success

    let id = UUID()
    let label: String
    let fn: Perform
    @MainActor @Published var state: QueueJobState<Progress, Success> = .pending
    @MainActor @Published var waitingFor = ObservableTaskDictionary()

    init(_ label: String, _ fn: @escaping Perform) {
        self.label = label
        self.fn = fn
    }
    
    lazy var deferred: DeferredTask<Success> = DeferredTask {
        let currentState = await self.state
        guard case .pending = currentState else {
            throw QueueJobError.invalidState("Expected pending job, but was \(currentState)")
        }

        do {
            await MainActor.run { self.state = .running }
            let result = try await self.fn(self)
            await MainActor.run { self.state = .complete(result) }
            return result
        } catch {
            await MainActor.run { self.state = .error(error) }
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
        
    func reportProgress(_ progress: Progress) async {
        await MainActor.run { self.state = .progress(progress) }
    }
    
    func waitFor<Success: Sendable, Progress: Sendable>(_ other: ObservableTask<Success, Progress>) async throws -> Success {
        await MainActor.run { waitingFor.insert(job: other) }
        let result = await other.task.result
        await MainActor.run { waitingFor.remove(job: other) }
        return try result.get()
    }
    
    func cancel(reason: String) {
        deferred.cancel()
        Task {
            await MainActor.run { self.state = .cancelled(reason: reason) }
        }
    }
    
    func cancel() {
        self.cancel(reason: "Unknown")
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
            print("onSettled:", id, result)
            await MainActor.run { handler(result) }
        }
        return self
    }
}

// actor AsyncJobQueue {
//
//
//    func execute<P: Sendable, R: Sendable>(job: ObservableTask<R, P>, fn: @escaping (ObservableTask<R, P>) async throws -> R) async {
//        let task = Task {
//            let currentState = await job.state
//            guard case .pending = currentState else {
//                throw QueueJobError.invalidState("Expected pending job, but was \(currentState)")
//            }
//
//            do {
//                await MainActor.run { job.state = .running }
//                let result = try await fn(job)
//                await MainActor.run { job.state = .complete(result) }
//                return result
//            } catch {
//                await MainActor.run { job.state = .error(error) }
//                throw error
//            }
//        }
//
//        await MainActor.run {
//            job.task = task
//        }
//    }
// }

class QueueJob<P, R>: Identifiable, ObservableObject, QueueJobProtocol {
    var anyState: QueueJobState<Any, Any> {
        switch state {
        case .complete(let result):
            return .complete(result)
        case .progress(let progress):
            return .progress(progress)
        case .pending: return .pending
        case .running: return .running
        case .error(let error): return .error(error)
        case .cancelled(reason: let reason): return .cancelled(reason: reason)
        }
    }
    
    typealias Perform = (_ job: QueueJob<P, R>) throws -> R
    let id = UUID()
    let label: String
    var queue: JobQueue?
    var execute: Perform
    @Published var state: QueueJobState<P, R>
    @Published var dependsOn: Set<UUID> = []
    
    init(label: String, state: QueueJobState<P, R>, execute: @escaping Perform) {
        self.label = label
        self.state = state
        self.execute = execute
        Task { print("hi") }
    }
    
    convenience init(_ label: String, _ execute: @escaping Perform) {
        self.init(label: label, state: .pending, execute: execute)
    }
    
    func runSubtask<P, R>(_ job: QueueJob<P, R>) throws -> R {
        if job.finalized {
            return try job.unwrap()
        }
        
        onMainAsync {
            self.dependsOn.insert(job.id)
            if let queue = self.queue {
                queue.insert(job: job)
            }
        }
        
        job.work { _ in }
        
        onMainAsync {
            self.dependsOn.remove(job.id)
        }
        
        return try job.unwrap()
    }
    
    func reportProgress(_ next: P) {
        onMainAsync {
            self.state = .progress(next)
        }
    }
    
    func cancel(reason: String) {
        onMainAsync {
            self.state = .cancelled(reason: reason)
        }
    }
    
    private func onMainAsync(_ run: @escaping () -> Void) {
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async {
                run()
            }
        }
    }
    
    func unwrap() throws -> R {
        switch state {
        case .complete(let result):
            return result
        case .cancelled(let reason):
            throw QueueJobError.dependencyCancelled(reason)
        case .error(let error): throw error
        default:
            throw QueueJobError.invalidState("Job not finalized: \(state)")
        }
    }
    
    func work(_ completionHandler: @escaping (QueueJob) -> Void) {
        guard !(running || finalized) else {
            let currentState = state
            onMainAsync {
                self.state = .error(QueueJobError.invalidState("Must be .pending to start, but was: \(currentState)"))
            }
            return
        }
        
        onMainAsync {
            self.state = .running
        }
        
        do {
            let result = try execute(self)
            onMainAsync {
                self.state = .complete(result)
                completionHandler(self)
            }
        } catch {
            onMainAsync {
                self.state = .error(error)
                completionHandler(self)
            }
        }
    }
}

/*
 
 func generateImage(params) {
    var generateJob = Job { job in
       let pipeline = job.runSubtask(Job("Get pileline") { getPipelineWorker() })
       let result = pipeline.run(params) { progress in
         job.reportProgress(progress)
       }
       return result
    }
    generateJob.completionHandler = generateJob
    queue.enqueue(generateJob)
    return generateJob
 }
 
 func getPipelineWorker() {
     if let pipeline = storage.get(pipeline) {
         return pipeline
     }
    return actuallyCreatePipeline()
 }
 
 */
