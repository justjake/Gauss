//
//  AssetDownloader.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/15/22.
//

import AppleArchive
import Foundation
import System

/// /ApplicationSupport/ts.jake.Gauss
///     /models
///         /sd2.0
///     /downloads
///         /sd2.0.aar.01
///         /sd2.0.aar.02
///         /sd2.0.zip
struct ApplicationSupportDir {
    static let inst = ApplicationSupportDir()
    
    var directoryName: String {
        Bundle.main.bundleIdentifier ?? "tl.jake.Gauss"
    }
    
    var directoryURL: URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportURL.appendingPathComponent(directoryName)
    }
    
    var modelsURL: URL {
        directoryURL.appendingPathComponent("models")
    }
    
    var downloadsURL: URL {
        directoryURL.appendingPathComponent("downloads")
    }
    
    func modelURL(_ model: GaussModel) -> URL {
        return modelsURL.appendingPathComponent(model.fileSystemName)
    }
}

// TODO: sha256, etc
// https://stackoverflow.com/questions/66143413/sha-256-of-large-file-using-cryptokit
struct SplitArchiveManifest: Codable {
    /// eg "sd2.aar"
    let destinationFile: String
    /// eg ["sd2.0.aar.01", "sd2.0.aar.02"]
    let archiveParts: [String]
    /// Final size when expanded. Presented as the rough estimate for downloading the zip parts.
    /// Used to decide if we should attempt to download the model or not
    let uncompressedSize: Measurement<UnitInformationStorage>
}

protocol AssetHost {
    func sourceURL(sourceFileName: String) -> URL
    func destinationFileName(sourceFileName: String) -> String
}

struct GithubRelease: AssetHost {
    var owner = "justjake"
    var repo = "Gauss"
    var tag: String
    
    /// Example URL:
    /// https://github.com/divamgupta/diffusionbee-stable-diffusion-ui/releases/download/1.5.1/DiffusionBee-1.5.1-arm64_MPS_SD1.5_FP16.dmg
    var baseURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/releases/download/\(tag)/")!
    }
    
    func destinationFileName(sourceFileName: String) -> String {
        "github-\(owner)-\(repo)-\(tag)-\(sourceFileName)"
    }
    
    func sourceURL(sourceFileName: String) -> URL {
        baseURL.appendingPathComponent(sourceFileName)
    }
}

struct TestAssetHost: AssetHost {
    let baseURL: URL
    let localPrefix: String
    
    func sourceURL(sourceFileName: String) -> URL {
        baseURL.appendingPathComponent(sourceFileName)
    }
    
    func destinationFileName(sourceFileName: String) -> String {
        "\(localPrefix)-\(sourceFileName)"
    }
}

func getManifest(for model: GaussModel) -> SplitArchiveManifest {
    switch model {
    case .sd2_0: return SplitArchiveManifest(
            destinationFile: "sd2.aar",
            archiveParts: [
                "sd2.aar.00",
                "sd2.aar.01"
            ],
            uncompressedSize: .init(value: 4913736, unit: .bytes)
        )
    case .sd1_4: return SplitArchiveManifest(
            destinationFile: "sd1.4.aar",
            archiveParts: [
                "sd1.4.aar.00",
                "sd1.4.aar.01"
            ],
            uncompressedSize: .init(value: 5226992, unit: .bytes)
        )
    case .sd1_5: return SplitArchiveManifest(
            destinationFile: "sd1.5.aar",
            archiveParts: [
                "sd1.5.aar.00",
                "sd1.5.aar.01"
            ],
            uncompressedSize: .init(value: 5226992, unit: .bytes)
        )
    }
}

// TODO: extend ObservableTask?
protocol BuildRule {
    var outputs: [URL] { get }
    var inputs: [URL] { get }
}

protocol CompositeBuildRule: BuildRule {
    var label: String { get }
    var rules: [BuildRule] { get }
}

extension [BuildRule] {
    var flattened: [any TaskableBuildRule] {
        var rules = [any TaskableBuildRule]()
        for rule in self {
            switch rule {
            case let composite as CompositeBuildRule:
                let subtasks = composite.rules.flattened
                rules.append(contentsOf: subtasks)
            case let taskable as any TaskableBuildRule:
                rules.append(taskable)
            default:
                continue
            }
        }
        return rules
    }
}

extension CompositeBuildRule {
    func graph() -> BuildTaskGraph {
        BuildTaskGraph(rules: rules.flattened, outputs: outputs)
    }
}

public struct BuildRuleList: CompositeBuildRule {
    var label: String
    var rules: [BuildRule]
    var inputs: [URL] {
        rules.flatMap { $0.inputs }
    }
    
    var outputs: [URL] {
        rules.flatMap { $0.outputs }
    }
}

protocol TaskableBuildRule: BuildRule {
    associatedtype BuildTask: ObservableTaskProtocol
    func createTask() -> BuildTask
}

struct TaskBuildRule: TaskableBuildRule {
    var inputs: [URL]
    var outputs: [URL]
    var label: String
    var build: (ObservableTask<Void, Void>) async throws -> Void
    
    func createTask() -> some ObservableTaskProtocol & AnyObject {
        return ObservableTask(label, build)
    }
}

extension URL {
    var mtime: Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[FileAttributeKey.modificationDate] as? Date
    }
    
    func touch() throws {
        let modificationDate = Date()
        try FileManager.default.setAttributes([FileAttributeKey.modificationDate: Date()], ofItemAtPath: path)
    }
}

extension BuildRule {
    func outputsOutOfDate() -> Bool {
        var outputTimestamps = [URL: Date]()
        for output in outputs {
            // Non-file outputs are always dirty.
            if !output.isFileURL {
                print("outputsOutOfDate: not a file URL, assuming out of date", output)
                return true
            }
            
            guard let mtime = output.mtime else {
                print("outputsOutOfDate: cannot fetch mtime, assuming out of date", output)
                return true
            }
            outputTimestamps[output] = mtime
        }
        
        guard let maxOutputTimestamp = outputTimestamps.values.max() else {
            return true
        }
        
        for input in inputs {
            // Non-file inputs are always clean.
            // TODO: HTTP HEAD??
            if !input.isFileURL {
                continue
            }
            
            if let mtime = input.mtime {
                if mtime > maxOutputTimestamp {
                    print("mtime of input \(mtime) > max mtime of output \(maxOutputTimestamp), is out of date", input)
                    return true
                }
            }
            
            // Note: missing input file still considered clean.
        }
        
        return false
    }
    
    func removeOutputs() throws {
        for output in outputs {
            if FileManager.default.fileExists(atPath: output.path) {
                try FileManager.default.removeItem(at: output)
            }
        }
    }
}

// TODO: make subclass of ObservableTask
struct DownloadRule {
    let manifesetFileName: String
    let remoteURL: URL
    let localURL: URL
    let expectedBytes: Measurement<UnitInformationStorage>
}

enum AssetDownloadError: Error {
    case invalidSuccess(String)
    case urlNotAFilePath(URL)
    case cannotOpenArchive(FilePath)
    case cannotDecompressArchive(FilePath)
    case cannotDecodeArchive(FilePath)
    case cannotStartExtraction(archive: FilePath, destination: FilePath)
    case unschedulableRule(BuildRule)
    case cannotMakeProgress(String)
}

// TODO: implement https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background
class DownloadTask: ObservableTask<URL, Progress>, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    public let rule: DownloadRule
    private var completed = FulfillableTask<Void>()
    private var downloadTask: URLSessionDownloadTask?
    
    init(_ job: DownloadRule) {
        self.rule = job
        // TODO: make it possible to use own method instead of closure
        super.init("Download \(job.manifesetFileName)") { _ in job.localURL }
    }
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "background-\(UUID())")
        // isDiscretionary - means do this slower. We want faster, so we can just start using
        // the data ASAP.
        // config.isDiscretionary = true
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private func createDownloadTask() -> URLSessionDownloadTask {
        let downloadTask = urlSession.downloadTask(with: rule.remoteURL)
        downloadTask.earliestBeginDate = Date.now
        downloadTask.countOfBytesClientExpectsToSend = 200
        downloadTask.countOfBytesClientExpectsToReceive = Int64(rule.expectedBytes.converted(to: .bytes).value)
        return downloadTask
    }
    
    // Called upon successful completion of the download
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            print("DownloadTask: finished download to temporary location:", location)
            try FileManager.default.createDirectory(at: rule.localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: rule.localURL)
            print("DownloadTask: moved to destination:", rule.localURL)
            completed.resolve(())
        } catch {
            print("DownloadTask: completion handler failed:", error)
            completed.reject(error)
        }
    }

    // Called when the download fails. We handle the
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let hasError = error {
            print("DownloadTask: failed:", hasError)
            completed.reject(hasError)
        } else {
            print("DownloadTask: succeeded, but need to call `didFinishDownloadingTo` too")
        }
    }
    
    override func work() async throws -> URL {
        print("DownloadTask: started for rule:", rule)
        let downloadTask = createDownloadTask()
        // TODO: figure out how to shimmy this assignment in case a parent task already observed the old progress instance... does this work?
        progress = downloadTask.progress
        print("DownloadTask: initialized progress:", progress)
        downloadTask.resume()
        _ = try await completed.task.value
        print("DownloadTask: done")
        return rule.localURL
    }
}

extension DownloadRule: TaskableBuildRule {
    var outputs: [URL] {
        [localURL]
    }
    
    var inputs: [URL] {
        [remoteURL]
    }
    
    func createTask() -> some ObservableTaskProtocol {
        return DownloadTask(self)
    }
}

struct ConcatFilesRule {
    let concat: [URL]
    let destination: URL
}

class ConcatFilesTask: ObservableTask<Void, Void> {
    public let rule: ConcatFilesRule
    private let bufferSize = 1024 * 1024 * 50
    
    init(_ rule: ConcatFilesRule) {
        self.rule = rule
        super.init("Assemble \(rule.concat.count) parts") { _ in () }
    }
    
    override func work() async throws {
        print("ConcatFilesTask: started for rule:", rule)
        let totalBytes = try rule.concat.map { input in
            let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
            let size = attributes[FileAttributeKey.size] as? NSNumber
            return size?.intValue ?? 0
        }.reduce(0) { $0 + $1 }
        progress.totalUnitCount = Int64(totalBytes)
        progress.fileTotalCount = rule.concat.count
        progress.fileOperationKind = .copying
        progress.fileCompletedCount = 0
        print("ConcatFilesTask: initialized progress:", progress)
        
        try FileManager.default.createDirectory(at: rule.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: rule.destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: rule.destination)

        for inputURL in rule.concat {
            print("ConcatFulesTask: concat file:", inputURL)
            let input = try FileHandle(forReadingFrom: inputURL)
            while true {
                guard let buffer = try input.read(upToCount: bufferSize) else {
                    break
                }
                if buffer.isEmpty {
                    break
                }
                output.write(buffer)
                progress.completedUnitCount += Int64(buffer.count)
                // TODO: await Task.yield() sometimes?
            }
            input.closeFile()
            progress.fileCompletedCount = (progress.fileCompletedCount ?? 0) + 1
            print("ConcatFilesTask: concat file complete:", inputURL)
            await Task.yield()
        }
        
        try output.synchronize()
        output.closeFile()
        print("ConcatFilesTask: done writing to output:", rule.destination)
    }
}

extension ConcatFilesRule: TaskableBuildRule {
    var outputs: [URL] {
        [destination]
    }
    
    var inputs: [URL] {
        concat
    }
    
    func createTask() -> some ObservableTaskProtocol {
        return ConcatFilesTask(self)
    }
}

struct UnarchiveFilesRule {
    let archiveFile: URL
    let destinationDirectory: URL
    // Note: we could add support for archive UTIType or something if we want to support .zip as well
}

extension UnarchiveFilesRule: TaskableBuildRule {
    var inputs: [URL] { [archiveFile] }
    var outputs: [URL] { [destinationDirectory] }
    func createTask() -> some ObservableTaskProtocol {
        return UnarchiveFilesTask(self)
    }
}

class UnarchiveFilesTask: ObservableTask<Void, Void> {
    let rule: UnarchiveFilesRule
    
    // TODO: actually calcuate this once work begins
    let estimatedFileCount = 30
    
    init(_ rule: UnarchiveFilesRule) {
        self.rule = rule
        super.init("Unpacking archive") { _ in () }
    }
    
    // See https://developer.apple.com/documentation/accelerate/decompressing_and_extracting_an_archived_directory
    func unarchiveToTempdir() throws -> URL {
        let destinationName = rule.destinationDirectory.pathComponents.last ?? "unknown"
        let tempName = "\(destinationName)-\(UUID())"
        let tempPath = NSTemporaryDirectory() + tempName
        print("UnarchiveFilesTask: will unarchive to tempdir:", tempPath)
        
        guard let inputFilePath = FilePath(rule.archiveFile) else {
            throw AssetDownloadError.urlNotAFilePath(rule.archiveFile)
        }
        
        guard let readFileStream = ArchiveByteStream.fileStream(
            path: inputFilePath,
            mode: .readOnly,
            options: [],
            permissions: FilePermissions(rawValue: 0o644)
        ) else {
            throw AssetDownloadError.cannotOpenArchive(inputFilePath)
        }
        
        guard let decompressStream = ArchiveByteStream.decompressionStream(readingFrom: readFileStream) else {
            throw AssetDownloadError.cannotDecodeArchive(inputFilePath)
        }
        defer {
            try? decompressStream.close()
        }
        
        guard let decodeStream = ArchiveStream.decodeStream(readingFrom: decompressStream) else {
            throw AssetDownloadError.cannotDecompressArchive(inputFilePath)
        }
        defer {
            try? decodeStream.close()
        }
        
        try FileManager.default.createDirectory(atPath: tempPath, withIntermediateDirectories: true)
        let tempFilePath = FilePath(tempPath)
        guard let extractStream = ArchiveStream.extractStream(extractingTo: tempFilePath,
                                                              flags: [.ignoreOperationNotPermitted])
        else {
            throw AssetDownloadError.cannotStartExtraction(archive: inputFilePath, destination: tempFilePath)
        }
        defer {
            try? extractStream.close()
        }
        
        _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream) /* { event, file, _ in
         switch event {
         case ArchiveHeader.EntryMessage.extractBegin:
         print("UnarchiveFilesTask: unarchiving file:", file)
         self.progress.completedUnitCount += 1
         case ArchiveHeader.EntryMessage.extractEnd:
         self.progress.completedUnitCount += 2
         self.progress.fileCompletedCount = (self.progress.fileCompletedCount ?? 0) + 1
         default:
         break
         }
                                                                                            
         return ArchiveHeader.EntryMessageStatus.ok
         } */
        print("UnarchiveFilesTask: done unarchiving all files")
        return URL(filePath: tempPath)
    }

    override func work() async throws {
        print("UnarchiveFilesTask: started for rule:", rule)
        // Set up progress
        progress.totalUnitCount = Int64(estimatedFileCount * 3) // 1 for start, 2 for finish
        progress.fileOperationKind = .decompressingAfterDownloading
        progress.fileTotalCount = estimatedFileCount
        // TODO: scan over the archive and actually count up all the bytes and such
        print("UnarchiveFilesTask: initialized progress:", progress)
        
        let tempUrl = try unarchiveToTempdir()
        
        try FileManager.default.createDirectory(at: rule.destinationDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: rule.destinationDirectory.path) {
            try FileManager.default.removeItem(at: rule.destinationDirectory)
        }
        try FileManager.default.moveItem(at: tempUrl, to: rule.destinationDirectory)
        try rule.destinationDirectory.touch()
        print("UnarchiveFilesTask: moved \(tempUrl) to \(rule.destinationDirectory)")
    }
}

let MAX_ZIP_PART_SIZE = Measurement<UnitInformationStorage>.init(value: 2, unit: .gigabytes)

struct DownloadModelRule {
    let model: GaussModel
    let assetHost: AssetHost
    
    var manifest: SplitArchiveManifest { getManifest(for: model) }
    
    var downloadJobs: [DownloadRule] { manifest.archiveParts.enumerated().map { DownloadRule(
        manifesetFileName: $0.element,
        remoteURL: assetHost.sourceURL(sourceFileName: $0.element),
        localURL: ApplicationSupportDir.inst.downloadsURL.appendingPathComponent(assetHost.destinationFileName(sourceFileName: $0.element)),
        expectedBytes: manifest.uncompressedSize
    ) }}
    
    var concatJob: ConcatFilesRule { ConcatFilesRule(
        concat: downloadJobs.map { $0.localURL },
        destination: ApplicationSupportDir.inst.downloadsURL.appendingPathComponent(assetHost.destinationFileName(sourceFileName: manifest.destinationFile))
    ) }
    
    var unzipJob: UnarchiveFilesRule {
        UnarchiveFilesRule(archiveFile: concatJob.destination, destinationDirectory: ApplicationSupportDir.inst.modelURL(model))
    }
    
    var intermediateOutputs: [URL] {
        return downloadJobs.flatMap(\.outputs) + concatJob.outputs
    }
    
    func removeIntermediateOutputs() throws {
        try downloadJobs.forEach { try $0.removeOutputs() }
        try concatJob.removeOutputs()
    }
}

// TODO:
extension DownloadModelRule: CompositeBuildRule {
    var label: String {
        "Install \(model.description)"
    }
    
    var inputs: [URL] {
        downloadJobs.map { $0.remoteURL }
    }
    
    var outputs: [URL] {
        [unzipJob.destinationDirectory]
    }
    
    var rules: [BuildRule] {
        return downloadJobs + [concatJob, unzipJob]
    }
}

struct DownloadAllModelsRule {
    let assetHost: AssetHost
    var downloadRules: [DownloadModelRule] {
        GaussModel.allCases.map { DownloadModelRule(model: $0, assetHost: assetHost) }
    }
}

extension DownloadAllModelsRule: CompositeBuildRule {
    var label: String {
        "Install all models"
    }
    
    var rules: [BuildRule] {
        downloadRules.map { $0 }
    }
    
    var outputs: [URL] {
        downloadRules.flatMap { $0.outputs }
    }
    
    var inputs: [URL] {
        downloadRules.flatMap { $0.inputs }
    }
}

// enum RuleExecutor {
//    static func executeInOrder(_ rules: [BuildRule]) async throws {
//        for rule in rules {
//            print("RuleScheduler.executeInOrder: rule", rule)
//            switch rule {
//            case let composite as CompositeBuildRule:
//                try await executeInOrder(composite.rules)
//            case let taskable as any TaskableBuildRule:
//                if taskable.outputsOutOfDate() {
//                    let task = taskable.createTask()
//                    task.resume()
//                    try await task.waitSuccess()
//                }
//            default:
//                throw AssetDownloadError.unschedulableRule(rule)
//            }
//        }
//    }
// }

protocol RuleScheduler {
    func schedule(rule: BuildRule) -> any ObservableTaskProtocol
}

class AssetManager: ObservableObject, ModelLocator {
    static let inst = AssetManager()
    
    @Published var cachedModelLocations = [GaussModel: URL]()
    @Published var loaded = false
    
    private let modelLocations = TryEachModelLocator(locators: [
        ApplicationSupportModelLocator()
//        BundleResourceModelLocator(),
//        DeveloperOnlyModelLocator()
    ])
    
    var hasModel: Bool {
        return firstModel != nil
    }
    
    var hasAllModels: Bool {
        return cachedModelLocations.count == GaussModel.allCases.count
    }
    
    var firstModel: GaussModel? {
        return GaussModel.allCases.first { locateModel(model: $0) != nil }
    }
    
    var defaultModel: GaussModel {
        return firstModel ?? GaussModel.Default
    }

    func locateModel(model: GaussModel) -> URL? {
        return cachedModelLocations[model]
    }
    
    @MainActor
    func refreshAvailableModels() async {
        for model in GaussModel.allCases {
            if let url = await Task(operation: { modelLocations.locateModel(model: model) }).value {
                cachedModelLocations[model] = url
            } else {
                cachedModelLocations.removeValue(forKey: model)
            }
            print("refreshAvailableModels:", cachedModelLocations)
        }
        loaded = true
    }
}

protocol ModelLocator {
    func locateModel(model: GaussModel) -> URL?
}

struct BundleResourceModelLocator: ModelLocator {
    func locateModel(model: GaussModel) -> URL? {
        return Bundle.main.url(forResource: model.fileSystemName, withExtension: nil)
    }
}

struct ApplicationSupportModelLocator: ModelLocator {
    func locateModel(model: GaussModel) -> URL? {
        let url = ApplicationSupportDir.inst.modelURL(model)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
}

struct DeveloperOnlyModelLocator: ModelLocator {
    func locateModel(model: GaussModel) -> URL? {
        let thisFileURL = URL(filePath: #file)
        let rootDirectory = thisFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let compiledModels = rootDirectory.appendingPathComponent("compiled-models")
        let url = compiledModels.appendingPathComponent(model.fileSystemName)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
}

struct TryEachModelLocator: ModelLocator {
    let locators: [ModelLocator]
    
    func locateModel(model: GaussModel) -> URL? {
        for locator in locators {
            if let url = locator.locateModel(model: model) {
                return url
            }
        }
        return nil
    }
}

extension Dictionary where Key: Any, Value: Any {
    mutating func upsert(forKey: Key, value: Value, updater: (inout Value) -> Value) {
        if var existing = self[forKey] {
            self[forKey] = updater(&existing)
        } else {
            self[forKey] = value
        }
    }
}

actor BuildTaskGraph {
    // TODO: we may need weak references in here
    typealias BuildRuleDictionary = [URL: [any TaskableBuildRule]]
    
    /// Check that output `URL` is up-to-date for rule BuildRule.
//    var isSatisfied: (_ output: URL, _ ofBuildRule: BuildRule) throws -> Bool
    
    var tasks = [any TaskableBuildRule]()
    var byInput = BuildRuleDictionary()
    var byOutput = BuildRuleDictionary()
    
    private var want = Set<URL>()
    private var building = Set<URL>()
    private var have = Set<URL>()
    
    var targets: [URL] {
        want.filter { !building.contains($0) && !have.contains($0) }
    }
    
    init(
        rules: [any TaskableBuildRule],
        outputs: [URL]
    ) {
        add(rules: rules)
        add(targets: outputs)
    }
    
    func add(rules: [any TaskableBuildRule]) {
        for rule in rules {
            add(rule: rule)
        }
    }
    
    func add(rule: any TaskableBuildRule) {
        tasks.append(rule)
        
        for input in rule.inputs {
            byInput.upsert(forKey: input, value: [rule]) { $0.append(rule); return $0 }
        }
        
        for output in rule.outputs {
            byOutput.upsert(forKey: output, value: [rule]) { $0.append(rule); return $0 }
        }
    }
    
    /// Call with the stuff you want to build.
    /// Returns the list of ruels to build next; they can all be built concurrently.
    func add(targets: [URL]) {
        targets.forEach { want.insert($0) }
    }
    
    /// Call when a artifact is produced, or if you have some artifacts initially that are know to be up-to-date.
    /// Returns the list of rules to build next; they can all be built concurrently.
    func addSatisfied(resources: [URL]) {
        resources.forEach { have.insert($0) }
        resources.forEach { building.remove($0) }
    }
    
    func didFinishBuilding(rules: [any TaskableBuildRule]) {
        addSatisfied(resources: rules.flatMap { $0.outputs })
    }
    
    /// Call when a rule is scheduled to be built.
    func willStartBuilding(rules: [any TaskableBuildRule]) {
        for rule in rules {
            rule.outputs.forEach { building.insert($0) }
            rule.outputs.forEach { have.remove($0) }
        }
    }
    
    func isSatisfied(input: URL) -> Bool {
        // Cached or recently built.
        if have.contains(input) {
            return true
        }
        
        // None-file inputs are always considered available.
        if !input.isFileURL {
            return true
        }
        
        if let rule = byOutput[input]?.first {
            return !rule.outputsOutOfDate()
        }
        
        return FileManager.default.fileExists(atPath: input.path)
    }
    
    /// Returns the rules that can currently be built.
    /// You can build all such rules concurrently.
    /// Once you start building rules, be sure to call `didStartBuilding(rules: buildableRules)`
    /// so the system doesn't return those rules anymore.
    func getBuildableRules() -> [any TaskableBuildRule] {
        // Inspect our want and our currently in-progress builds, then suggest
        // which builds we should start
        var results = [any TaskableBuildRule]()
        var toVisitQueue = [any TaskableBuildRule]()
        var hasVisitedSet = Set<URL>()
        
        // Start from the rules that produce the targets we need
        toVisitQueue.append(contentsOf: rulesForTargets(targets: Array(want)))
        
        while !toVisitQueue.isEmpty {
            let rule = toVisitQueue.removeFirst()
            
            // Prevent circular
            if rule.outputs.allSatisfy({ hasVisitedSet.contains($0) }) {
                continue
            }
            rule.outputs.forEach { hasVisitedSet.insert($0) }
            
            // If we already satisfied the output, skip.
            if rule.outputs.allSatisfy({ isSatisfied(input: $0) }) {
                addSatisfied(resources: rule.outputs)
                continue
            }
            
            // If we can start building the rule, add it to return set.
            if readyToBuild(rule: rule) {
                results.append(rule)
                continue
            }
            
            // Otherwise, check to see if we can build its dependencies
            toVisitQueue.append(contentsOf: rulesForTargets(targets: rule.inputs))
        }
        
        return results
    }
    
    func readyToBuild(rule: BuildRule) -> Bool {
        if !rule.inputs.allSatisfy({ isSatisfied(input: $0) }) {
            // Must have all inputs to build.
            return false
        }
        
        if !rule.outputs.allSatisfy({ !building.contains($0) }) {
            // Must not be building any outputs already.
            return false
        }
        
        return rule.outputsOutOfDate()
    }
    
    func rulesForTargets(targets: [URL]) -> [any TaskableBuildRule] {
        return targets.compactMap { target in
            byOutput[target]?.first
        }
    }
}
