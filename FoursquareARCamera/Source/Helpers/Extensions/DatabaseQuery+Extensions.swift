//
//  DatabaseQuery+Extensions.swift
//  FoursquareARCamera
//
//  Created by Jiang on 1/11/18.
//  Copyright © 2018 Project Dent. All rights reserved.
//

import Foundation
import Firebase
import RxSwift
import ObjectMapper


extension BaseMappable {
    static var firebaseIdKey : String {
        get {
            return "FirebaseIdKey"
        }
    }
    init?(snapshot: DataSnapshot) {
        guard var json = snapshot.value as? [String: Any] else {
            return nil
        }
        json[Self.firebaseIdKey] = snapshot.key as Any
        
        self.init(JSON: json)
    }
}

extension DatabaseQuery {
    
    func rx_observeSingleEvent(of event: DataEventType) -> Observable<DataSnapshot> {
        return Observable.create({ (observer) -> Disposable in
            self.observeSingleEvent(of: event, with: { (snapshot) in
                observer.onNext(snapshot)
                observer.onCompleted()
            }, withCancel: { (error) in
                observer.onError(error)
            })
            return Disposables.create()
        })
    }
    
    func rx_observeEvent(event: DataEventType) -> Observable<DataSnapshot> {
        return Observable.create({ (observer) -> Disposable in
            let handle = self.observe(event, with: { (snapshot) in
                observer.onNext(snapshot)
            }, withCancel: { (error) in
                observer.onError(error)
            })
            return Disposables.create {
                self.removeObserver(withHandle: handle)
            }
        })
    }
}


extension Mapper {
    func mapArray(snapshot: DataSnapshot) -> [N] {
        return snapshot.children.map { (child) -> N? in
            if let childSnap = child as? DataSnapshot {
                return N(snapshot: childSnap)
            }
            return nil
            //flatMap here is a trick
            //to filter out `nil` values
            }.flatMap { $0 }
    }
}
