//
//  ViewController.swift
//  FoursquareARCamera
//
//  Created by Gareth Paul Jones on 02/07/2017.
//  Copyright © 2017 Foursquare. All rights reserved.
//

import UIKit
import SceneKit 
import MapKit
import CocoaLumberjack
import Alamofire
import SwiftyJSON
import Mapbox
import Reachability
import RxSwift
import RxCocoa
import RealmSwift
import RxRealm
import SSZipArchive
import ARKit
import CoreLocation
import Firebase
import ObjectMapper

class ViewController: UIViewController, MKMapViewDelegate, MGLMapViewDelegate, SceneLocationViewDelegate, SSZipArchiveDelegate {
    
    var dragOnInfinitePlanesEnabled = false
    
    let sceneLocationView = SceneLocationView()

    var subway =  CLLocation()
    
    let mapView = MKMapView()
    
    var geoFire: GeoFire!

    var userAnnotation: MKPointAnnotation?
    var locationEstimateAnnotation: MKPointAnnotation?
    var compass : MBXCompassMapView!
    var updateUserLocationTimer: Timer?
    
    ///Whether to show a map view
    ///The initial value is respected
    var showMapView: Bool = false
    
    var centerMapOnUserLocation: Bool = true
    
    ///Whether to display some debugging data
    ///This currently displays the coordinate of the best location estimate
    ///The initial value is respected
    var displayDebugging = false
    
    var infoLabel = UILabel()
    
    let plusButton = UIButton()
    
    var updateInfoLabelTimer: Timer?
    
    var loaded: Bool = false
    
    var adjustNorthByTappingSidesOfScreen = false

    private var disposeBag = DisposeBag()
    
    let updateScheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "Test.ARKit.CoreLocation.updateQueue")
    var objects = Variable<[VirtualObject]>([])
    let DEFAULT_DISTANCE_CAMERA_TO_OBJECTS = Float(10)

    var models: Variable<[Model]> = Variable([])
    
    var currentLocation: CLLocation?
    
    var isModelDisplaying = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
  
        // Check internet connectivity
        checkInternetConnectivity()
    
        // Setup UI controls
        setupUIControls()
        
        // Bind objects
        bindObjects()
        
        // Load models
        loadModelsList()
        
        // Get current location in best accuracy
//        getCurrentLocation()
        
        // Initialize GeoFire
        let firebaseRef = Database.database().reference().child("feeds")
        geoFire = GeoFire(firebaseRef: firebaseRef)
    }
    
    private func checkInternetConnectivity() {
        
        let reach = Reachability()!
        
        if reach.connection.description == "No Connection" {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Oops", message: "We are currently struggling to access to the internet. This app requires access to the internet in order to find locations around you.", preferredStyle: UIAlertControllerStyle.alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default) { action in
                    // perhaps use action.title here
                })
                self.present(alert, animated: true)
            }
        }
    }
    
    private func setupUIControls() {
        
        // Add Plus Button
        let imgPlus = UIImage.init(named: "plus")
        plusButton.frame = CGRect(x: self.view.frame.width / 2 - 40,
                                  y: self.view.frame.height-120,
                                  width: 80,
                                  height: 80)
        plusButton.center.x = self.view.center.x
        plusButton.setImage(imgPlus, for: .normal)
        plusButton.addTarget(self, action: #selector(plusButtonTapped), for: .touchUpInside)
        plusButton.isEnabled = false // It will be enabled once you get user's current
        
        // Add Scene Location
        
        sceneLocationView.addSubview(plusButton)
        sceneLocationView.showAxesNode = true
        sceneLocationView.locationDelegate = self
        
        view.addSubview(sceneLocationView)
        
        // Add the compass to the View
        // See https://blog.mapbox.com/compass-for-arkit-42c0692c4e51
        compass = MBXCompassMapView(frame: CGRect(x: self.view.frame.width - 110,
                                                  y:  self.view.frame.height - 160,
                                                  width: 100,
                                                  height: 100),
                                    styleURL: URL(string: "mapbox://styles/mapbox/navigation-guidance-day-v2"))
        compass.isMapInteractive = false
        compass.tintColor = .black
        compass.delegate = self
        view.addSubview(compass)
        
        // Setup Tap Gesture
        let tapGesture = UITapGestureRecognizer(target: self,  action: #selector(self.handleTap(_:)))
        
        self.sceneLocationView.isUserInteractionEnabled = true
        self.sceneLocationView.addGestureRecognizer(tapGesture)
    }
    
    private func bindObjects() {
        objects.asObservable().subscribe(onNext: { (objects) in
            if let newObject = objects.last {
                self.loadVirtualObject(object: newObject)
            }
        }).disposed(by: disposeBag)
    }
    
    private func loadVirtualObject(object: VirtualObject) {
        
        let compassMarker = MGLPointAnnotation()
        compassMarker.coordinate = object.location.coordinate
        self.compass.addAnnotation(compassMarker)
        
        object.viewController = self
        VirtualObjectsManager.shared.addVirtualObject(virtualObject: object)
        VirtualObjectsManager.shared.setVirtualObjectSelected(virtualObject: object)
        
        object.loadModel()
        
        self.sceneLocationView.scene.rootNode.addChildNode(object)
        self.sceneLocationView.updatePosition(object: object)
    }
    
    private func loadModelsList() {
        
        // Load Firebase Feeds
        getModels().subscribe(onNext: { (models) in
            self.models.value.append(contentsOf: models)
        }, onError: { (error) in
            print(error.localizedDescription)
        }).disposed(by: disposeBag)
    }
    
    private func getModels() -> Observable<[Model]> {
        
        let ref = Database.database().reference().child("models")
        return ref.rx_observeSingleEvent(of: .value)
            .map{Mapper<Model>().mapArray(snapshot: $0)}
    }
    
    private func getCurrentLocation() {
        var locationManager = CLLocationManager()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.rx.didUpdateLocations
            .subscribe(onNext: { (locations) in
                if let location = locations.first, location.horizontalAccuracy <= 10, location.verticalAccuracy < 5 {
                    self.currentLocation = location
                    self.plusButton.isEnabled = true
                    locationManager.stopUpdatingLocation()
                    locationManager.delegate = nil
                }
            }, onCompleted: {
                print("Completed")
            }).disposed(by: disposeBag)
        locationManager.startUpdatingLocation()
    }
    
    // MARK: Virtual Object Manipulation
    
    func moveVirtualObjectToPosition(_ pos: SCNVector3?, _ instantly: Bool, _ filterPosition: Bool) {
        
        guard let newPosition = pos else {
            return
        }
        
        if instantly {
            setNewVirtualObjectPosition(newPosition)
        } else {
            updateVirtualObjectPosition(newPosition, filterPosition)
        }
    }
    
    func worldPositionFromScreenPosition(_ position: CGPoint,
                                         objectPos: SCNVector3?,
                                         infinitePlane: Bool = false) -> (position: SCNVector3?,
        planeAnchor: ARPlaneAnchor?,
        hitAPlane: Bool) {
            
            // -------------------------------------------------------------------------------
            // 1. Always do a hit test against exisiting plane anchors first.
            //    (If any such anchors exist & only within their extents.)
            
            let planeHitTestResults = sceneLocationView.hitTest(position, types: .existingPlaneUsingExtent)
            if let result = planeHitTestResults.first {
                
                let planeHitTestPosition = SCNVector3.positionFromTransform(result.worldTransform)
                let planeAnchor = result.anchor
                
                // Return immediately - this is the best possible outcome.
                return (planeHitTestPosition, planeAnchor as? ARPlaneAnchor, true)
            }
            
            // -------------------------------------------------------------------------------
            // 2. Collect more information about the environment by hit testing against
            //    the feature point cloud, but do not return the result yet.
            
            var featureHitTestPosition: SCNVector3?
            var highQualityFeatureHitTestResult = false
            
            let highQualityfeatureHitTestResults =
                sceneLocationView.hitTestWithFeatures(position, coneOpeningAngleInDegrees: 18, minDistance: 0.2, maxDistance: 2.0)
            
            if !highQualityfeatureHitTestResults.isEmpty {
                let result = highQualityfeatureHitTestResults[0]
                featureHitTestPosition = result.position
                highQualityFeatureHitTestResult = true
            }
            
            // -------------------------------------------------------------------------------
            // 3. If desired or necessary (no good feature hit test result): Hit test
            //    against an infinite, horizontal plane (ignoring the real world).
            
            if (infinitePlane && dragOnInfinitePlanesEnabled) || !highQualityFeatureHitTestResult {
                
                let pointOnPlane = objectPos ?? SCNVector3Zero
                
                let pointOnInfinitePlane = sceneLocationView.hitTestWithInfiniteHorizontalPlane(position, pointOnPlane)
                if pointOnInfinitePlane != nil {
                    return (pointOnInfinitePlane, nil, true)
                }
            }
            
            // -------------------------------------------------------------------------------
            // 4. If available, return the result of the hit test against high quality
            //    features if the hit tests against infinite planes were skipped or no
            //    infinite plane was hit.
            
            if highQualityFeatureHitTestResult {
                return (featureHitTestPosition, nil, false)
            }
            
            // -------------------------------------------------------------------------------
            // 5. As a last resort, perform a second, unfiltered hit test against features.
            //    If there are no features in the scene, the result returned here will be nil.
            
            let unfilteredFeatureHitTestResults = sceneLocationView.hitTestWithFeatures(position)
            if !unfilteredFeatureHitTestResults.isEmpty {
                let result = unfilteredFeatureHitTestResults[0]
                return (result.position, nil, false)
            }
            
            return (nil, nil, false)
    }
    
    func setNewVirtualObjectPosition(_ pos: SCNVector3) {
        
        guard let object = VirtualObjectsManager.shared.getVirtualObjectSelected(),
            let cameraTransform = sceneLocationView.session.currentFrame?.camera.transform else {
                return
        }
        
        let cameraWorldPos = SCNVector3.positionFromTransform(cameraTransform)
        var cameraToPosition = pos - cameraWorldPos
        cameraToPosition.setMaximumLength(DEFAULT_DISTANCE_CAMERA_TO_OBJECTS)
        
        object.position = cameraWorldPos + cameraToPosition
        
        if object.parent == nil {
            sceneLocationView.scene.rootNode.addChildNode(object)
        }
    }
    
    func updateVirtualObjectPosition(_ pos: SCNVector3, _ filterPosition: Bool) {
        guard let object = VirtualObjectsManager.shared.getVirtualObjectSelected() else {
            return
        }
        
        guard let cameraTransform = sceneLocationView.session.currentFrame?.camera.transform else {
            return
        }
        
        let cameraWorldPos = SCNVector3.positionFromTransform(cameraTransform)
        var cameraToPosition = pos - cameraWorldPos
        cameraToPosition.setMaximumLength(DEFAULT_DISTANCE_CAMERA_TO_OBJECTS)
        
        // Compute the average distance of the object from the camera over the last ten
        // updates. If filterPosition is true, compute a new position for the object
        // with this average. Notice that the distance is applied to the vector from
        // the camera to the content, so it only affects the percieved distance of the
        // object - the averaging does _not_ make the content "lag".
        
        if filterPosition {
            let averagedDistancePos = cameraWorldPos + cameraToPosition
            object.position = averagedDistancePos
        } else {
            object.position = cameraWorldPos + cameraToPosition
        }
    }
    
    // MARK: Animations
    @objc
    func plusButtonTapped() {
        let modelsTableVC = ModelsTableViewController()
        let navVC = UINavigationController(rootViewController: modelsTableVC)
        
        modelsTableVC.model.subscribe(onNext: { (model) in
            navVC.dismiss(animated: true, completion: nil)
            
            // download model assets
            if model.isSaved() {
                print("Already exists.")
                let id = "\(model.id)_\(Int(Date().timeIntervalSince1970))"
                self.showModel(id: id, at: self.currentLocation!.coordinate, isNeedToPost: true)
            } else {
                self.downloadModel(for: model)
            }
        }, onError: { (error) in
            print(error.localizedDescription)
        }).disposed(by: disposeBag)
        
        self.present(navVC, animated: true, completion: nil)
    }
    
    private func showModel(id: String, at coordinate: CLLocationCoordinate2D, isNeedToPost: Bool = false) {
        
        // Load model
        guard let modelId = id.components(separatedBy: "_").first else { return }
        
        let realm = try! Realm()
        let object = realm.objects(ModelObject.self).filter({$0.id == modelId}).first!
        let location = CLLocation.init(coordinate: coordinate, altitude: self.currentLocation!.altitude - 1.4)
        
        isModelDisplaying = false
        
        let virtualObject = VirtualObject(id: id, with: object, location: location)
        self.objects.value.append(virtualObject)
        
        // Post to Firebase Database
        if isNeedToPost {
            geoFire.setLocation(location, forKey: id) { (error) in
                if error == nil {
                    print("Posted.")
                } else {
                    print(error!.localizedDescription)
                }
            }
        }
    }
    
    private func downloadModel(for model: Model, showAt location: CLLocation? = nil) {
        
        print("Downloading assets.")
        isModelDisplaying = true
        
        let downloader = ModelDownloader(model: model)
        downloader.downloadZipFile()
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { (request) in
                request.resume()
            }, onError: { (error) in
                self.isModelDisplaying = false
                print(error.localizedDescription)
            }, onCompleted: {
                print("Downloaded .zip file")
                let filePath = model.destinationURL().path
                var fileSize : UInt64
                
                do {
                    //return [FileAttributeKey : Any]
                    let attr = try FileManager.default.attributesOfItem(atPath: filePath)
                    fileSize = attr[FileAttributeKey.size] as! UInt64
                    
                    //if you convert to NSDictionary, you can get file size old way as well.
                    let dict = attr as NSDictionary
                    fileSize = dict.fileSize()
                    print(fileSize)
                } catch {
                    self.isModelDisplaying = false
                    print("Error: \(error)")
                }
                self.extractZipFile(for: model, showAt: location)
            }).disposed(by: disposeBag)
    }
    
    private func putModel(for model: Model) {
        
    }
    
    private func extractZipFile(for model: Model, showAt location: CLLocation?) {
        unzipFile(for: model).subscribe(onNext: { (progress) in
            print("subs")
        }, onError: { (error) in
            self.isModelDisplaying = false
            print(error.localizedDescription)
        }, onCompleted: {
            print("Unzipping completed")
            let fileManager = FileManager.default
            
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: model.directoryURL(), includingPropertiesForKeys: nil)
                for url in fileURLs {
                    if url.pathExtension != "zip" {
                        let assetsURLs = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                        for fileURL in assetsURLs {
                            
                            if fileURL.pathExtension == "scn" ||
                                fileURL.pathExtension == "dae" {
                                print("Found .scn file.")
                                print(FileManager.default.fileExists(atPath: fileURL.path))
                                let modelObject = ModelObject.modelObject(with: model, modelUrl: fileURL)
                                let realm = try! Realm()
                                realm.beginWrite()
                                realm.add(modelObject)
                                try! realm.commitWrite()
                                
                                let currentCoordinate = location ?? self.currentLocation!
                                let id = "\(model.id)_\(Int(Date().timeIntervalSince1970))"
                                self.showModel(id: id, at: currentCoordinate.coordinate, isNeedToPost: true)
                            }
                        }
                    }
                }
            } catch {
                self.isModelDisplaying = false
                print("Error while enumerating files.")
            }
        }).disposed(by: disposeBag)
    }
    
    var unzipProgressSubject : PublishSubject<Progress>?
    
    func unzipFile(for model: Model) -> Observable<Progress> {
        if let subject = unzipProgressSubject {
            subject.dispose()
        }
        
        unzipProgressSubject = PublishSubject()
        
        let unzipObservable = Observable<Progress>.create { observer in
            SSZipArchive.unzipFile(atPath: model.destinationURL().path, toDestination: model.directoryURL().path, delegate: self)
            observer.onCompleted()
            
            return Disposables.create()
        }
        
        let mergeObservable = Observable.of(unzipProgressSubject!, unzipObservable).merge(maxConcurrent: 2)
        
        return mergeObservable
    }
    
    //MARK: - Zip Delegate
    func zipArchiveDidUnzipArchive(atPath path: String, zipInfo: unz_global_info, unzippedPath: String) {
        print("done")
        unzipProgressSubject?.onCompleted()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DDLogDebug("run")
        sceneLocationView.run()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        DDLogDebug("pause")
        // Pause the view's session
        sceneLocationView.pause()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        sceneLocationView.frame = CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: self.view.frame.size.height)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    
    // MARK: Geolocation
    
    func getNearbyLocations(_ currentLocation: CLLocation) {
        guard let center = self.currentLocation else { return }
        // Query locations at [37.7832889, -122.4056973] with a radius of 600 meters
        let circleQuery = geoFire.query(at: center, withRadius: 0.1)
        
        circleQuery?.observe(.keyEntered, with: { (key, location) in
            if let key = key, let location = location, !self.isModelDisplaying {
             
                // return if already exists in scenelocationview
                if self.objects.value.contains(where: {return $0.id == key}) { return }
                guard let id = key.components(separatedBy: "_").first else { return }
                guard let model = self.models.value.filter({$0.id == id}).first else { return }
                if !model.isSaved() {
                    self.downloadModel(for: model, showAt: location)
                } else {
                    self.showModel(id: key, at: location.coordinate)
                }
            }
        })
        
        circleQuery?.observeReady({
            
        })
    }
    
    // MARK: Get foursquare locations
    
    func getFoursquareLocations(_ currentLocation:CLLocation) {
        
        // Check if the request has loaded to avoid multuple requests.
        if self.loaded == false  {
            self.loaded = true
            let lat = String(currentLocation.coordinate.latitude)
            let lng = String(currentLocation.coordinate.longitude)
            let client_id = "WP35TUWLL4V5MZN2T3MSTZOP3MLGOQFQFPHKWU2ZXWRPRWHL"
            let client_secret = "GF4T52L0BJC5OIPBMBWEV44G2GAFVXIMGZDK4OGYQGCPBFRO"
            let categoryId = "4d4b7105d754a06374d81259" // food
            let ll = lat + "," + lng
            let url = "https://api.foursquare.com/v2/venues/search?v=20161016&ll=\(ll)&client_id=\(client_id)&client_secret=\(client_secret)&limit=5&categoryId=\(categoryId)&radius=200"
            
            // Send HTTP request
            Alamofire.request(url).responseJSON { response in
                switch response.result {
                case .success(let value):
                    let json = JSON(value)
                    let resp = json["response"]
                    let venues = resp["venues"]
                    // Iterate through the venues
                    for venue in venues {
                        let name = (venue.1["name"])
                        let lat = venue.1["location"]["lat"]
                        let lng = venue.1["location"]["lng"]
                        let categoryName = venue.1["categories"][0]["name"]
                        let ratingStr = Int(venue.1["location"]["distance"].double! * 3.28084)
                        
                        let frameSize = CGRect(x: 0, y: 0, width: 362, height: 291)
                        let fsview = FSQView(frame: frameSize)
                        fsview.venueName.text = name.string
                        fsview.categoryName.text = categoryName.string
                        fsview.ratingStr.text = "\(ratingStr)ft"
                        
                        var image = UIImage.imageWithView(view: fsview)
                        
                        
                        // Mask an image to avoid pixelated images in AR.
                        let m = UIImage(named: "fsqMask")!
                        image = UIImage.aImage(image: image, mask:m)
                        image = UIImage.resizeImage(image: image, newHeight: 200)
                        
                        let starbucksCoordinate = CLLocationCoordinate2D(latitude: lat.double!, longitude: lng.double!)
                        let starbucksLocation = CLLocation(coordinate: starbucksCoordinate, altitude: 30.84)
                        let starbucksImage = image
//                        let starbucksLocationNode = LocationAnnotationNode(location: starbucksLocation, image: starbucksImage)


                         let tapGesture = UITapGestureRecognizer(target: self,  action: #selector(self.handleTap(_:)))
                        
                        self.sceneLocationView.isUserInteractionEnabled = true
                        self.sceneLocationView.addGestureRecognizer(tapGesture)
                        
//                        self.sceneLocationView.addLocationNodeWithConfirmedLocation(locationNode: starbucksLocationNode)

                        let compassMarker = MGLPointAnnotation()
                        compassMarker.coordinate = starbucksCoordinate
                        self.compass.addAnnotation(compassMarker)
                        
                    }
                    
                case .failure(let error):
                    print(error)
                }
            }
            
        }
    }
    
    
    
    @objc
    func handleTap(_ gestureRecognize: UIGestureRecognizer) {
        // retrieve the SCNView
        let scnView = self.sceneLocationView// as! ARSCNView
        
        // check what nodes are tapped
        let p = gestureRecognize.location(in: scnView)
        let hitResults = scnView.hitTest(p, options: [:])
        // check that we clicked on at least one object
        if hitResults.count > 0 {
            // retrieved the first clicked object
            let result = hitResults[0]
            
            let spin = CABasicAnimation(keyPath: "rotation")
            // Use from-to to explicitly make a full rotation around z
            spin.fromValue = SCNVector4(x: 0, y: 1, z: 0, w: 0)
            spin.toValue = SCNVector4(x: 0, y: 1, z: 0, w: Float(2 * CGFloat.pi))
            spin.duration = 3
            spin.repeatCount = 1
            
            if let node = result.node.parent {
                node.addAnimation(spin, forKey: "spin around")
            } else {
                result.node.addAnimation(spin, forKey: "spin around")
            }
        }
    }
    
    
    
    // MARK: Update the user location
    
    @objc func updateUserLocation() {
        
        if let currentLocation = self.currentLocation {
            DispatchQueue.main.async {
                if let bestEstimate = self.sceneLocationView.bestLocationEstimate(),
                    let position = self.sceneLocationView.currentScenePosition() {
                    
                    self.getFoursquareLocations(currentLocation)
                    DDLogDebug("")
                    DDLogDebug("Fetch current location")
                    DDLogDebug("best location estimate, position: \(bestEstimate.position), location: \(bestEstimate.location.coordinate), accuracy: \(bestEstimate.location.horizontalAccuracy), date: \(bestEstimate.location.timestamp)")
                    DDLogDebug("current position: \(position)")
                    DDLogDebug("altitude: \(currentLocation.altitude)")
                    
                    let translation = bestEstimate.translatedLocation(to: position)
                    
                    DDLogDebug("translation: \(translation)")
                    DDLogDebug("translated location: \(currentLocation)")
                    DDLogDebug("")
                }
                
                if self.userAnnotation == nil {
                    self.userAnnotation = MKPointAnnotation()
                    self.mapView.addAnnotation(self.userAnnotation!)
                }
                
                UIView.animate(withDuration: 0.5, delay: 0, options: UIViewAnimationOptions.allowUserInteraction, animations: {
                    self.userAnnotation?.coordinate = currentLocation.coordinate
                }, completion: nil)
            
                if self.centerMapOnUserLocation {
                    UIView.animate(withDuration: 0.45, delay: 0, options: UIViewAnimationOptions.allowUserInteraction, animations: {
                        self.mapView.setCenter(self.userAnnotation!.coordinate, animated: false)
                    }, completion: {
                        _ in
                        self.mapView.region.span = MKCoordinateSpan(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
                    })
                }
                
                if self.displayDebugging {
                    let bestLocationEstimate = self.sceneLocationView.bestLocationEstimate()
                    
                    if bestLocationEstimate != nil {
                        if self.locationEstimateAnnotation == nil {
                            self.locationEstimateAnnotation = MKPointAnnotation()
                            self.mapView.addAnnotation(self.locationEstimateAnnotation!)
                        }
                        
                        self.locationEstimateAnnotation!.coordinate = bestLocationEstimate!.location.coordinate
                    } else {
                        if self.locationEstimateAnnotation != nil {
                            self.mapView.removeAnnotation(self.locationEstimateAnnotation!)
                            self.locationEstimateAnnotation = nil
                        }
                    }
                }
            }
        }
    }
    
    // MARK: Update the label information
    
    @objc func updateInfoLabel() {
        if let position = sceneLocationView.currentScenePosition() {
            infoLabel.text = "x: \(String(format: "%.2f", position.x)), y: \(String(format: "%.2f", position.y)), z: \(String(format: "%.2f", position.z))\n"
        }
        
        if let eulerAngles = sceneLocationView.currentEulerAngles() {
            infoLabel.text!.append("Euler x: \(String(format: "%.2f", eulerAngles.x)), y: \(String(format: "%.2f", eulerAngles.y)), z: \(String(format: "%.2f", eulerAngles.z))\n")
        }
        
        if let heading = sceneLocationView.locationManager.heading,
            let accuracy = sceneLocationView.locationManager.headingAccuracy {
            infoLabel.text!.append("Heading: \(heading)º, accuracy: \(Int(round(accuracy)))º\n")
        }
        
        let date = Date()
        let comp = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        
        if let hour = comp.hour, let minute = comp.minute, let second = comp.second, let nanosecond = comp.nanosecond {
            infoLabel.text!.append("\(String(format: "%02d", hour)):\(String(format: "%02d", minute)):\(String(format: "%02d", second)):\(String(format: "%03d", nanosecond / 1000000))")
        }
    }
    
    //MARK: SceneLocationViewDelegate
    
    func sceneLocationViewDidAddSceneLocationEstimate(sceneLocationView: SceneLocationView, position: SCNVector3, location: CLLocation) {
        
        // Add Foursquare Location
//        self.getFoursquareLocations(location)
        
        DDLogDebug("add scene location estimate, position: \(position), location: \(location.coordinate), accuracy: \(location.horizontalAccuracy), altitude: \(location.altitude), date: \(location.timestamp)")
        if location.horizontalAccuracy < 10, location.verticalAccuracy < 5 {
                self.currentLocation = location
        }
        if self.currentLocation != nil {
            self.plusButton.isEnabled = true
            getNearbyLocations(self.currentLocation!)
        }
    }
    
    func sceneLocationViewDidRemoveSceneLocationEstimate(sceneLocationView: SceneLocationView, position: SCNVector3, location: CLLocation) {
        DDLogDebug("remove scene location estimate, position: \(position), location: \(location.coordinate), accuracy: \(location.horizontalAccuracy), date: \(location.timestamp)")
    }
    
    func sceneLocationViewDidConfirmLocationOfNode(sceneLocationView: SceneLocationView, node: LocationNode) {
    }
    
    func sceneLocationViewDidSetupSceneNode(sceneLocationView: SceneLocationView, sceneNode: SCNNode) {
        
    }
    
    func sceneLocationViewDidUpdateLocationAndScaleOfLocationNode(sceneLocationView: SceneLocationView, locationNode: LocationNode) {
        
    }
}

extension DispatchQueue {
    func asyncAfter(timeInterval: TimeInterval, execute: @escaping () -> Void) {
        self.asyncAfter(
            deadline: DispatchTime.now() + Double(Int64(timeInterval * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: execute)
    }
}

extension UIView {
    func recursiveSubviews() -> [UIView] {
        var recursiveSubviews = self.subviews
        
        for subview in subviews {
            recursiveSubviews.append(contentsOf: subview.recursiveSubviews())
        }
        
        return recursiveSubviews
    }
}
