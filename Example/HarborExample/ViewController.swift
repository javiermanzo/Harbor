//
//  ViewController.swift
//  HarborExample
//
//  Created by Javier Manzo on 21/02/2023.
//

import UIKit

final class ViewController: UIViewController {

    let myButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Request", for: .normal)
        button.setTitleColor(.black, for: .normal)
        button.backgroundColor = .systemBlue
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .green
        
        view.addSubview(myButton)
        
        NSLayoutConstraint.activate([
            myButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            myButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            myButton.widthAnchor.constraint(equalToConstant: 100),
            myButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        myButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
    }
    
    @objc func buttonTapped()  {
        Task {
            let textAlert: String
            let response = await KanyeQuoteGetRequest().request()
            
            switch response {
            case .success(let result):
                textAlert = result.quote
            case .noChanges:
                textAlert = "No Changes"
            case .cancelled:
                textAlert = "Request Cancelled"
            case .error:
                textAlert = "Request Error"
            }
            
            self.presentAlert(title: "Request Info", message: textAlert)
        }
    }
    
    func presentAlert(title: String, message: String) {
        DispatchQueue.main.async { [weak self] in
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            
            let okAction = UIAlertAction(title: "OK", style: .default) { (action) in
                // Acción a realizar cuando se presione el botón OK
            }
            
            alertController.addAction(okAction)
            
            self?.present(alertController, animated: true, completion: nil)
        }
    }
    
}

