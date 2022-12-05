//
//  GaussDocument.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/3/22.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var gaussNotebook: UTType {
        UTType(exportedAs: "tl.jake.gauss.notebook", conformingTo: .package)
    }
    
    static var gaussPrompt: UTType {
        UTType(exportedAs: "tl.jake.gauss.prompt", conformingTo: .json)
    }
    
    static var gaussPromptId: UTType {
        UTType(exportedAs: "tl.jake.gauss.id", conformingTo: .json)
    }
}

enum GaussSeed: Codable {
    case random;
    case fixed(Int)
}

struct GaussPromptId: Codable {
    let ID: UUID
}

extension GaussPromptId: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .gaussPromptId)
    }
}

enum GaussModel: Hashable, Equatable, Codable {
    case sd2
    case sd1_4
    case sd1_5
    case custom(URL)
    
    static var Default: GaussModel = .sd1_5
}


struct GaussPrompt: Identifiable, Codable, Sendable {
    // App concerns
    var id = UUID()
    var createdAt = Date.now
    var results: [GaussResult] = []
    var title: String? = nil
    var favorite = false
    var hidden = false

    // ML parameters
    var text = ""
    var negativeText = ""
    
    var guidance = 7.5
    var steps = 10.0
    var seed = GaussSeed.random
    var safety = false
    var model: GaussModel = GaussModel.Default
    
    var width = 512
    var height = 512
    
    func clone() -> Self {
        var copy = self
        let defaults = Self()
        copy.id = defaults.id
        copy.createdAt = defaults.createdAt
        copy.results = defaults.results
        copy.favorite = defaults.favorite
        copy.hidden = defaults.hidden
        return copy
    }
}

extension GaussPrompt: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .gaussPrompt)
        ProxyRepresentation(exporting: \.text) { GaussPrompt(text: $0) }
        ProxyRepresentation(exporting: \.promptId) // TODO: flumoxed by .visibility
    }
    
    var promptId: GaussPromptId {
        GaussPromptId(ID: id)
    }
}

struct GaussImageRef: Identifiable, Codable {
    var id = UUID()
    var createdAt = Date.now
    var unsafe: Bool = false
        
    var title: String? = nil
    var favorite = false
    var hidden = false
}

struct GaussResult: Identifiable, Codable {
    var id = UUID()
    var createdAt = Date.now
    var promptId: UUID
    var images: [GaussImageRef]
}

struct GaussPersistedData: Codable {
    let id: UUID
    let prompts: [GaussPrompt]
    let composer: GaussPrompt
}

extension NSImage {
    func toPngData() -> Data {
        let imageRepresentation = NSBitmapImageRep(data: self.tiffRepresentation!)
        return (imageRepresentation?.representation(using: .png, properties: [:])!)!
    }
}

extension NSImage: Transferable  {
    static public var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) {
            return $0.toPngData()
        }
    }
}

typealias GaussImages = [String : NSImage]

extension GaussImages {
    func getImage(ref: GaussImageRef) -> NSImage? {
        return self[ref.id.uuidString]
    }
    
    mutating func addImage(ref: GaussImageRef, _ image: NSImage) {
        self[ref.id.uuidString] = image
    }
    
    mutating func removePrompt(_ prompt: GaussPrompt) {
        for result in prompt.results {
            removeResult(result)
        }
    }
    
    mutating func removeResult(_ result: GaussResult) {
        for image in result.images {
            removeImage(ref: image)
        }
    }
    
    mutating func removeImage(ref: GaussImageRef) {
        removeValue(forKey: ref.id.uuidString)
    }
}

struct GaussDocument: FileDocument, Identifiable {
    static let JSON_DATA_NAME = "data.json"
    static let IMAGE_DIRECTORY_NAME = "images"
    
    var id: UUID
    var prompts: [GaussPrompt]
    var composer: GaussPrompt
    var images: [String : NSImage] = [:]
    
    init(
        id: UUID = UUID(),
        prompts: [GaussPrompt] = [],
        images: [String : NSImage] = [:],
        composer: GaussPrompt = GaussPrompt()
    ) {
        self.id = id
        self.prompts = prompts
        self.images = images
        self.composer = composer
    }

    static var readableContentTypes: [UTType] { [.gaussNotebook] }

    init(configuration: ReadConfiguration) throws {
        guard let jsonFile = configuration.file.fileWrappers?[GaussDocument.JSON_DATA_NAME],
              let jsonFileData = jsonFile.regularFileContents,
              let imageDirectory = configuration.file.fileWrappers?[GaussDocument.IMAGE_DIRECTORY_NAME],
              let imageFiles = imageDirectory.fileWrappers
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let decoded = try JSONDecoder().decode(GaussPersistedData.self, from: jsonFileData)
        self.id = decoded.id
        self.prompts = decoded.prompts
        self.composer = decoded.composer
        
        for (name, imageWrapper) in imageFiles {
            if let data = imageWrapper.regularFileContents {
                let image = NSImage(data: data)
                self.images[name] = image
            }
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let persisted = GaussPersistedData(id: self.id, prompts: self.prompts, composer: self.composer)
        let jsonData = try JSONEncoder().encode(persisted)
        let jsonFileWrapper = FileWrapper(regularFileWithContents: jsonData)
        jsonFileWrapper.preferredFilename = GaussDocument.JSON_DATA_NAME
        
        let imagesFileWrapper = FileWrapper(directoryWithFileWrappers: [String : FileWrapper]())
        imagesFileWrapper.preferredFilename = GaussDocument.IMAGE_DIRECTORY_NAME
        for (name, image) in self.images {
            let imageFile = FileWrapper(regularFileWithContents: image.toPngData())
            imageFile.preferredFilename = name
            imagesFileWrapper.addFileWrapper(imageFile)
        }
        
        let outputFileWrapper = FileWrapper(directoryWithFileWrappers: [
            GaussDocument.JSON_DATA_NAME: jsonFileWrapper,
            GaussDocument.IMAGE_DIRECTORY_NAME: imagesFileWrapper,
        ])
        
        return outputFileWrapper
    }
}
