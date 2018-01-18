/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Wrapper SceneKit node for virtual objects placed into the AR scene.
*/

import Foundation
import SceneKit
import ARKit
import CoreLocation

public class VirtualObject: SCNNode {
    static let ROOT_NAME = "Virtual object root node"
    
    var id: String = ""
    var modelId: String = ""
    var modelURL: URL?
    var thumbnailURL: URL? = nil
    var audioURL: URL? = nil
    var defaultScale: SCNVector3 = SCNVector3One
    var location = CLLocation()
    
    var viewController: ViewController?
    
    override init() {
        super.init()
        
        self.name = VirtualObject.ROOT_NAME
    }
    
    init(id: String, with object: ModelObject, thumbnailURL: URL? = nil, audioURL: URL? = nil, location: CLLocation) {
        super.init()
        self.id = id
        self.modelId = object.id
        self.modelURL = URL(string: object.modelUrl)!
        self.thumbnailURL = thumbnailURL
        self.audioURL = audioURL
        self.defaultScale = SCNVector3(object.scale, object.scale, object.scale)
        self.location = location
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Use average of recent virtual object distances to avoid rapid changes in object scale.
    var recentVirtualObjectDistances = [Float]()
    
    func loadModel() {
        let fileName = self.modelURL!.lastPathComponent
        var directory = self.modelURL!.path
        directory.removeSubrange(directory.range(of: fileName)!)
        do {
            let virtualObjectScene = try SCNScene(url: self.modelURL!, options: nil)
            let wrapperNode = SCNNode()
            
            for child in virtualObjectScene.rootNode.childNodes {
                child.geometry?.firstMaterial?.lightingModel = .physicallyBased
                child.movabilityHint = .movable
                wrapperNode.addChildNode(child)
            }
            wrapperNode.scale = self.defaultScale
            self.addChildNode(wrapperNode)
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func unloadModel() {
        for child in self.childNodes {
            child.removeFromParentNode()
        }
    }
    
    func translateBasedOnScreenPos(_ pos: CGPoint, instantly: Bool, infinitePlane: Bool) {
        guard let controller = viewController else {
            return
        }
        let result = controller.worldPositionFromScreenPosition(pos, objectPos: self.position, infinitePlane: infinitePlane)
        controller.moveVirtualObjectToPosition(result.position, instantly, !result.hitAPlane)
    }
}

extension VirtualObject {
    
    static func isNodePartOfVirtualObject(_ node: SCNNode) -> Bool {
        if node.name == VirtualObject.ROOT_NAME {
            return true
        }
        
        if node.parent != nil {
            return isNodePartOfVirtualObject(node.parent!)
        }
        
        return false
    }
}

// MARK: - Protocols for Virtual Objects

protocol ReactsToScale {
	func reactToScale()
}

extension SCNNode {
	
	func reactsToScale() -> ReactsToScale? {
		if let canReact = self as? ReactsToScale {
			return canReact
		}
		
		if parent != nil {
			return parent!.reactsToScale()
		}
		
		return nil
	}
}
