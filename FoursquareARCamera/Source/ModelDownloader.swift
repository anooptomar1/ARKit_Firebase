//
//  ModelDownloader.swift
//  ARKitExample
//
//  Created by Jesse Ziegler on 9/6/17.
//  Copyright © 2017 Apple. All rights reserved.
//

import Foundation
import SSZipArchive
import ObjectMapper
import RxAlamofire
import Alamofire
import RxSwift
import RxCocoa
import RxRealm
import Realm
import RealmSwift
import CoreLocation

protocol ModelDownloaderDelegate: class {
    func didFinishDownload()
    func didFinishAllDownloads(model: Model)
}

class Model: Mappable {
    
    var id = ""
    var title = ""
    var modelUrl = ""
    var audioUrl = ""
    var imageUrl = ""
    var armodelUrl = ""
    var temporaryURL = ""
    var scale: Double = 1
    
    func mapping(map: Map) {
        id <- map["id"]
        title <- map["title"]
        modelUrl <- map["url"]
        audioUrl <- map["audio"]
        imageUrl <- map["image"]
        scale <- map["scale"]
    }
    
    required init?(map: Map) {
        
    }
    
    func isSaved() -> Bool {
//        return FileManager.default.fileExists(atPath: self.destinationURL().path)
        let realm = try! Realm()
        let models = realm.objects(ModelObject.self)
        return models.contains(where: {self.id == $0.id})
    }
    
    func directoryURL() -> URL {
        let documentsPath = NSSearchPathForDirectoriesInDomains(
            .documentDirectory,
            .userDomainMask,
            true
            ).first ?? ""
        let documentsURL = URL(fileURLWithPath: documentsPath)
        let directory: String = "ar_assets/asset_\(self.id)_files"
        let extractedFilesURL = documentsURL.appendingPathComponent(directory)
        return extractedFilesURL
    }
    
    func destinationURL() -> URL {
        let documentsPath = NSSearchPathForDirectoriesInDomains(
            .documentDirectory,
            .userDomainMask,
            true
            ).first ?? ""
        let documentsURL = URL(fileURLWithPath: documentsPath)
        let directory: String = "ar_assets/asset_\(self.id)_files"
        let extractedFilesURL = documentsURL.appendingPathComponent(directory)
        let fileUrl = extractedFilesURL.appendingPathComponent(self.id + ".zip")
        return fileUrl
    }
}

class ModelObject: Object {
    @objc dynamic var id = ""
    @objc dynamic var title = ""
    @objc dynamic var modelUrl = ""
    @objc dynamic var scale: CGFloat = 1
    var coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    
    static func modelObject(with model: Model, modelUrl: URL) -> ModelObject {
        
        let object = ModelObject()
        
        object.id = model.id
        object.title = model.title
        object.modelUrl = modelUrl.standardizedFileURL.absoluteString
        object.scale = CGFloat(model.scale)
        
        return object
    }
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

final class ModelDownloader {

    private let disposeBag = DisposeBag()
    private let model: Model

    init(model: Model) {
        self.model = model
    }
    
    func downloadZipFile() -> Observable<DownloadRequest> {
        let documentsPath = NSSearchPathForDirectoriesInDomains(
            .documentDirectory,
            .userDomainMask,
            true
            ).first ?? ""
        let documentsURL = URL(fileURLWithPath: documentsPath)
        let directory: String = "ar_assets/asset_\(model.id)_files"
        let extractedFilesURL = documentsURL.appendingPathComponent(directory)
        let destinationUrl = extractedFilesURL.appendingPathComponent(model.id + ".zip")
        let fileManager = FileManager.default
        
        do {
            try fileManager.createDirectory(at: extractedFilesURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print(error.localizedDescription)
        }
        let urlRequest = try! URLRequest(url: URL(string: model.modelUrl)!, method: .get)
        
        return download(urlRequest) { (tempUrl, response) -> (destinationURL: URL, options: DownloadRequest.DownloadOptions) in
            return (destinationUrl, .createIntermediateDirectories)
        }
    }

    static func modelAlreadyDownloaded(model: Model) -> Bool {
		
        let documentsPath = NSSearchPathForDirectoriesInDomains(
            .documentDirectory,
            .userDomainMask,
            true
            ).first ?? ""
        let documentsURL = URL(fileURLWithPath: documentsPath)
        let directory: String = "ar_assets/asset_\(model.id)_files"
        let extractedFilesURL = documentsURL.appendingPathComponent(directory)
        let fileUrl = extractedFilesURL.appendingPathComponent(model.id + ".zip")
        
        return FileManager.default.fileExists(atPath: fileUrl.absoluteString)
    }
}
