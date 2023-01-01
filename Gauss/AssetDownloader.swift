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
        let directory: String = {
            switch model {
            case .sd1_4: return "sd1.4"
            case .sd2_0: return "sd2.0"
            case .sd1_5: return "sd1.5"
            }
        }()
        
        return modelsURL.appendingPathComponent(directory)
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
    var outputs: [URL] { get }
    var inputs: [URL] { get }
    var rules: [BuildRule] { get }
}

protocol TaskableBuildRule: BuildRule {
    func createTask() -> any ObservableTaskProtocol
}

extension URL {
    var mtime: Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: absoluteString)
        return attributes?[FileAttributeKey.modificationDate] as? Date
    }
}

extension BuildRule {
    func outputsOutOfDate() throws -> Bool {
        var outputTimestamps = [URL: Date]()
        for output in outputs {
            // Non-file outputs are always dirty.
            if !output.isFileURL {
                return true
            }
            
            guard let mtime = output.mtime else {
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
                    return true
                }
            }
            
            // Note: missing input file still considered clean.
        }
        
        return false
    }
    
    func removeOutputs() throws {
        for output in outputs {
            if FileManager.default.fileExists(atPath: output.absoluteString) {
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
}

// TODO: implement https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background
class DownloadTask: ObservableTask<URL, Progress>, URLSessionDelegate, URLSessionTaskDelegate {
    public let rule: DownloadRule
    private var completed = FulfillableTask<Void>()
    private var downloadTask: URLSessionDownloadTask?
    
    init(_ job: DownloadRule) {
        self.rule = job
        // TODO: make it possible to use own method instead of closure
        super.init("Download \(job.manifesetFileName)") { _ in job.localURL }
    }
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "background")
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
        downloadTask.delegate = self
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
            try FileManager.default.moveItem(at: location, to: rule.localURL)
            print("DownloadTask: moved to destination:", rule.localURL)
            completed.fulfill(result: .success(()))
        } catch {
            completed.fulfill(result: .failure(error))
        }
    }

    // Called when the download fails. We handle the
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let hasError = error {
            print("DownloadTask: failed:", hasError)
            completed.fulfill(result: .failure(hasError))
        } else {
            completed.fulfill(result: .failure(AssetDownloadError.invalidSuccess("Should succeed elsewhere")))
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
    
    func createTask() -> any ObservableTaskProtocol {
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
            let attributes = try FileManager.default.attributesOfItem(atPath: input.absoluteString)
            let size = attributes[FileAttributeKey.size] as? NSNumber
            return size?.intValue ?? 0
        }.reduce(0) { $0 + $1 }
        progress.totalUnitCount = Int64(totalBytes)
        progress.fileTotalCount = rule.concat.count
        progress.fileOperationKind = .copying
        progress.fileCompletedCount = 0
        print("ConcatFilesTask: initialized progress:", progress)
        
        let output = try FileHandle(forWritingTo: rule.destination)

        for inputURL in rule.concat {
            print("ConcatFulesTask: concat file:", inputURL)
            let input = try FileHandle(forReadingFrom: inputURL)
            do {
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
    
    func createTask() -> any ObservableTaskProtocol {
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
    func createTask() -> any ObservableTaskProtocol {
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
    override func work() async throws {
        print("UnarchiveFilesTask: started for rule:", rule)
        // Set up progress
        progress.totalUnitCount = Int64(estimatedFileCount * 3) // 1 for start, 2 for finish
        progress.fileOperationKind = .decompressingAfterDownloading
        progress.fileTotalCount = estimatedFileCount
        // TODO: scan over the archive and actually count up all the bytes and such
        print("UnarchiveFilesTask: initialized progress:", progress)
        
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
        
        if !FileManager.default.fileExists(atPath: tempPath) {
            try FileManager.default.createDirectory(atPath: tempPath,
                                                    withIntermediateDirectories: false)
        }
        
        let tempFilePath = FilePath(tempPath)
        guard let extractStream = ArchiveStream.extractStream(extractingTo: tempFilePath,
                                                              flags: [.ignoreOperationNotPermitted])
        else {
            throw AssetDownloadError.cannotStartExtraction(archive: inputFilePath, destination: tempFilePath)
        }
        defer {
            try? extractStream.close()
        }
        
        _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream) { event, file, _ in
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
        }
        print("UnarchiveFilesTask: done unarchiving all files")
        
        try FileManager.default.moveItem(at: URL(filePath: tempPath), to: rule.destinationDirectory)
        print("UnarchiveFilesTask: moved \(tempPath) to \(rule.destinationDirectory)")
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

enum RuleScheduler {
    static func executeInOrder(_ rules: [BuildRule]) async throws {
        for rule in rules {
            switch rule {
            case let composite as CompositeBuildRule:
                try await executeInOrder(composite.rules)
            case let taskable as TaskableBuildRule:
                if try taskable.outputsOutOfDate() {
                    let task = taskable.createTask()
                    task.resume()
                    try await task.waitSuccess()
                }
            default:
                throw AssetDownloadError.unschedulableRule(rule)
            }
        }
    }
}
