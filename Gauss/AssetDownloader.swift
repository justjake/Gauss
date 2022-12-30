//
//  AssetDownloader.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/15/22.
//

import Foundation

/// /ApplicationSupport/ts.jake.Gauss
///     /models
///         /sd2.0
///     /downloads
///         /sd2.0.zip.01
///         /sd2.0.zip.02
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
struct SplitZipFileManifest: Codable {
    /// eg "sd2.0.zip"
    let destinationFile: String
    /// eg ["sd2.0.zip.01", "sd2.0.zip.02"]
    let zipParts: [String]
    /// Final size when expanded. Presented as the rough estimate for downloading the zip parts.
    /// Used to decide if we should attempt to download the model or not
    let uncompressedSize: Measurement<UnitInformationStorage>
}

struct GithubRelease {
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
}

func getManifest(for model: GaussModel) -> SplitZipFileManifest? {
    switch model {
    case .sd2_0: return SplitZipFileManifest(
            destinationFile: "sd2.0.zip",
            zipParts: [
                "sd2.0.zip.01",
                "sd2.0.zip.02"
            ],
            uncompressedSize: .init(value: 4913736, unit: .bytes)
        )
    case .sd1_4: return SplitZipFileManifest(
            destinationFile: "sd1.4.zip",
            zipParts: [
                "sd1.4.zip.01",
                "sd1.4.zip.02"
            ],
            uncompressedSize: .init(value: 5226992, unit: .bytes)
        )
    case .sd1_5: return SplitZipFileManifest(
            destinationFile: "sd1.5",
            zipParts: [
                "sd1.5.zip.01",
                "sd1.5.zip.02"
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

// TODO: implement https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background
class DownloadTask: ObservableTask<URL, Progress>, URLSessionDelegate, URLSessionTaskDelegate {
    public let rule: DownloadRule
    private var continuation: CheckedContinuation<Void, Error>?
    
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
        progress = downloadTask.progress
        return downloadTask
    }
    
    override func work() async throws -> URL {
        let task = createDownloadTask()
        try await withCheckedContinuation { done in self.continuation = done }
        task.resume()
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

struct ConcatFilesJob {
    let concat: [URL]
    let destination: URL
}

extension ConcatFilesJob: BuildRule {
    var outputs: [URL] {
        [destination]
    }
    
    var inputs: [URL] {
        concat
    }
}

struct UnzipFileJob {
    let zipFile: URL
    let destinationDirectory: URL
}

extension UnzipFileJob: BuildRule {
    var inputs: [URL] { [zipFile] }
    var outputs: [URL] { [destinationDirectory] }
}

let MAX_ZIP_PART_SIZE = Measurement<UnitInformationStorage>.init(value: 2, unit: .gigabytes)

struct DownloadModelJob2 {
    let model: GaussModel
    let release: GithubRelease
    
    var manifest: SplitZipFileManifest { getManifest(for: model)! }
    
    var downloadJobs: [DownloadRule] { manifest.zipParts.enumerated().map { DownloadRule(
        manifesetFileName: $0.element,
        remoteURL: release.baseURL.appendingPathComponent($0.element),
        localURL: ApplicationSupportDir.inst.downloadsURL.appendingPathComponent(release.destinationFileName(sourceFileName: $0.element)),
        expectedBytes: manifest.uncompressedSize / Double(manifest.zipParts.count)
    ) }}
    
    var concatJob: ConcatFilesJob { ConcatFilesJob(
        concat: downloadJobs.map { $0.localURL },
        destination: ApplicationSupportDir.inst.downloadsURL.appendingPathComponent(release.destinationFileName(sourceFileName: manifest.destinationFile))
    ) }
    
    var unzipJob: UnzipFileJob {
        UnzipFileJob(zipFile: concatJob.destination, destinationDirectory: ApplicationSupportDir.inst.modelURL(model))
    }
    
    func removeIntermediateOutputs() throws {
        try downloadJobs.forEach { try $0.removeOutputs() }
        try concatJob.removeOutputs()
    }
}

// TODO:
extension DownloadModelJob2: BuildRule {
    var inputs: [URL] {
        downloadJobs.map { $0.remoteURL }
    }
    
    var outputs: [URL] {
        [unzipJob.destinationDirectory]
    }
}

struct DownloadAllModelsJob {
    let release: GithubRelease
    var jobs: [DownloadModelJob2] {
        GaussModel.allCases.map { DownloadModelJob2(model: $0, release: release) }
    }
}

// TODO:
extension DownloadAllModelsJob: BuildRule {
    var outputs: [URL] {
        jobs.flatMap { $0.outputs }
    }
    
    var inputs: [URL] {
        jobs.flatMap { $0.inputs }
    }
}