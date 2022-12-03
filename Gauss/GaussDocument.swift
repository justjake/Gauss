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
}

enum GaussSeed: Codable {
    case random;
    case fixed(Int)
}

struct GaussPrompt: Identifiable, Codable {
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
    
    var guidance = 5.0
    var steps = 10.0
    var seed = GaussSeed.random
    
    var width = 512
    var height = 512
}

struct GaussResult: Identifiable, Codable {
    var id = UUID()
    var createdAt = Date.now
    var promptId: UUID
    var imageId: UUID
    
    var title: String? = nil
    var favorite = false
    var hidden = false
}

struct GaussPersistedData: Codable {
    let id: UUID
    let prompts: [GaussPrompt]
}

extension NSImage {
    func toPngData() -> Data {
        let imageRepresentation = NSBitmapImageRep(data: self.tiffRepresentation!)
        return (imageRepresentation?.representation(using: .png, properties: [:])!)!
    }
}

typealias GaussImages = [String : NSImage]

struct GaussDocument: FileDocument, Identifiable {
    static let JSON_DATA_NAME = "data.json"
    static let IMAGE_DIRECTORY_NAME = "images"
    
    var id: UUID
    var prompts: [GaussPrompt]
    var images: [String : NSImage] = [:]
    
    init(
        id: UUID = UUID(),
        prompts: [GaussPrompt] = [GaussPrompt()],
        images: [String : NSImage] = [:]
    ) {
        self.id = id
        self.prompts = prompts
        self.images = images
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
        
        for (name, imageWrapper) in imageFiles {
            if let data = imageWrapper.regularFileContents {
                let image = NSImage(data: data)
                self.images[name] = image
            }
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let persisted = GaussPersistedData(id: self.id, prompts: self.prompts)
        let jsonData = try JSONEncoder().encode(persisted)
        let jsonFileWrapper = FileWrapper(regularFileWithContents: jsonData)
        jsonFileWrapper.filename = GaussDocument.JSON_DATA_NAME
        
        let imagesFileWrapper = FileWrapper(directoryWithFileWrappers: [String : FileWrapper]())
        for (name, image) in self.images {
            let imageFile = FileWrapper(regularFileWithContents: image.toPngData())
            imageFile.filename = name
            imagesFileWrapper.addFileWrapper(imageFile)
        }
        
        let outputFileWrapper = FileWrapper(directoryWithFileWrappers: [
            GaussDocument.JSON_DATA_NAME: jsonFileWrapper,
            GaussDocument.IMAGE_DIRECTORY_NAME: imagesFileWrapper,
        ])
        
        return outputFileWrapper
    }
}
