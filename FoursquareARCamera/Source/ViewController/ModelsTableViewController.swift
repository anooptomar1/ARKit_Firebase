//
//  ModelsTableViewController.swift
//  FoursquareARCamera
//
//  Created by Jiang on 1/10/18.
//  Copyright © 2018 Project Dent. All rights reserved.
//

import UIKit
import Firebase
import RxSwift
import RxCocoa
import ObjectMapper

class ModelsTableViewController: UITableViewController {

    let cellIdentifier = "ModelsTableViewController"
    var models: Variable<[Model]> = Variable([])
    let disposeBag = DisposeBag()
    
    // model
    let model = PublishSubject<Model>()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup TableView
        setupUI()
        
        // Load models
        bindTableView()
        bindTableViewSelected()
        loadModelsList()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    private func setupUI() {
        
        // Add Cancel button
        let cancelBarButtonItem = UIBarButtonItem.init(title: "Cancel", style: .done, target: self, action: #selector(cancelClicked))
        self.navigationItem.leftBarButtonItem = cancelBarButtonItem
        
        // setup TableView
        self.tableView.delegate = nil
        self.tableView.dataSource = nil
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellIdentifier)
        self.tableView.rowHeight = 80.0
        self.tableView.tableFooterView = UIView()
    }
    
    
    // MARK: Bind TableView
    
    private func bindTableView() {
        models.asObservable()
            .bind(to: tableView.rx.items(cellIdentifier: cellIdentifier, cellType: UITableViewCell.self)) {row, element, cell in
                cell.textLabel?.text = element.title
            }.disposed(by: disposeBag)
    }
    
    private func bindTableViewSelected() {
        tableView.rx.modelSelected(Model.self)
            .subscribe(onNext: { (model) in
                self.model.onNext(model)
            }, onError: { (error) in
                print(error.localizedDescription)
            }).disposed(by: disposeBag)
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
    
    @objc private func cancelClicked() {
        self.navigationController?.dismiss(animated: true, completion: nil)
    }
}
