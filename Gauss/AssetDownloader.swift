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
            case .custom(let url):
                let safeURL = String(describing: url).replacing(try! Regex("[^\\w]")) { _ in "" }
                return "custom-\(safeURL)"
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
    let owner = "justjake"
    let repo = "Gauss"
    let tag: String
    
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

func getManifest(for model: GaussModel) -> SplitArchiveManifest? {
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
    case .custom:
        return nil
    }
}

// TODO: extend ObservableTask?
protocol BuildRule {
    var outputs: [URL] { get }
    var inputs: [URL] { get }
}

protocol CompositeBuildRule: BuildRule {
    var rules: [BuildRule] { get }
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

// TODO: re-impement make
struct BuildPipelineRule {
    let rules: [any BuildRule]
    
    func planTarget(target: BuildRule) throws -> BuildRule {
        // TODO:
        throw QueueJobError.invalidState("not implemented")
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
            try FileManager.default.moveItem(at: location, to: rule.localURL)
            completed.fulfill(result: .success(()))
        } catch {
            completed.fulfill(result: .failure(error))
        }
    }

    // Called when the download fails. We handle the
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let hasError = error {
            completed.fulfill(result: .failure(hasError))
        } else {
            completed.fulfill(result: .failure(AssetDownloadError.invalidSuccess("Should succeed elsewhere")))
        }
    }
    
    override func work() async throws -> URL {
        let downloadTask = createDownloadTask()
        // TODO: figure out how to shimmy this assignment in case a parent task already observed the old progress instance... does this work?
        progress = downloadTask.progress
        downloadTask.resume()
        _ = try await completed.task.value
        return rule.localURL
    }
}

extension DownloadRule: BuildRule {
    var outputs: [URL] {
        [localURL]
    }
    
    var inputs: [URL] {
        [remoteURL]
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
        let totalBytes = try rule.concat.map { input in
            let attributes = try FileManager.default.attributesOfItem(atPath: input.absoluteString)
            let size = attributes[FileAttributeKey.size] as? NSNumber
            return size?.intValue ?? 0
        }.reduce(0) { $0 + $1 }
        progress.totalUnitCount = Int64(totalBytes)
        progress.fileTotalCount = rule.concat.count
        progress.fileOperationKind = .copying
        progress.fileCompletedCount = 0
        
        let output = try FileHandle(forWritingTo: rule.destination)

        for inputURL in rule.concat {
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
            await Task.yield()
        }
        
        output.closeFile()
    }
}

extension ConcatFilesRule: BuildRule {
    var outputs: [URL] {
        [destination]
    }
    
    var inputs: [URL] {
        concat
    }
}

struct UnarchiveFilesRule {
    let archiveFile: URL
    let destinationDirectory: URL
    // Note: we could add support for archive UTIType or something if we want to support .zip as well
}

extension UnarchiveFilesRule: BuildRule {
    var inputs: [URL] { [archiveFile] }
    var outputs: [URL] { [destinationDirectory] }
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
        // Set up progress
        progress.totalUnitCount = Int64(estimatedFileCount * 3) // 1 for start, 2 for finish
        progress.fileOperationKind = .decompressingAfterDownloading
        progress.fileTotalCount = estimatedFileCount
        // TODO: scan over the archive and actually count up all the bytes and such
        
        let destinationName = rule.destinationDirectory.pathComponents.last ?? "unknown"
        let tempName = "\(destinationName)-\(UUID())"
        let tempPath = NSTemporaryDirectory() + tempName
        
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
        
        _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream) { event, _, _ in
            switch event {
            case ArchiveHeader.EntryMessage.extractBegin:
                self.progress.completedUnitCount += 1
            case ArchiveHeader.EntryMessage.extractEnd:
                self.progress.completedUnitCount += 2
                self.progress.fileCompletedCount = (self.progress.fileCompletedCount ?? 0) + 1
            default:
                break
            }
            
            return ArchiveHeader.EntryMessageStatus.ok
        }
    }
}

let MAX_ZIP_PART_SIZE = Measurement<UnitInformationStorage>.init(value: 2, unit: .gigabytes)

struct DownloadModelRule {
    let model: GaussModel
    let assetHost: AssetHost
    
    var manifest: SplitArchiveManifest { getManifest(for: model)! }
    
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
    
    func removeIntermediateOutputs() throws {
        try downloadJobs.forEach { try $0.removeOutputs() }
        try concatJob.removeOutputs()
    }
}

// TODO:
extension DownloadModelRule: BuildRule {
    var inputs: [URL] {
        downloadJobs.map { $0.remoteURL }
    }
    
    var outputs: [URL] {
        [unzipJob.destinationDirectory]
    }
}

struct DownloadAllModelsRule {
    let assetHost: AssetHost
    var jobs: [DownloadModelRule] {
        GaussModel.allCases.map { DownloadModelRule(model: $0, assetHost: assetHost) }
    }
}

// TODO:
extension DownloadAllModelsRule: BuildRule {
    var outputs: [URL] {
        jobs.flatMap { $0.outputs }
    }
    
    var inputs: [URL] {
        jobs.flatMap { $0.inputs }
    }
}
