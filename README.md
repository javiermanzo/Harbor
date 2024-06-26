<p align="center" width="100%">
    <img width="40%" src="https://raw.githubusercontent.com/javiermanzo/Harbor/main/Resources/Harbor.png"> 
</p>

![Swift](https://img.shields.io/badge/Swift-5-orange?style=flat-square) ![Platforms](https://img.shields.io/badge/Platforms-iOS-yellowgreen?style=flat-square) ![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Harbor.svg?style=flat-square) ![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)

# Harbor

Harbor is a library for making API requests in Swift in a simple way using async/await.

##  Requirements 

- Swift 5
- iOS 13.0

## Installation

You can add Harbor to your project using [CocoaPods](https://cocoapods.org/) or [Swift Package Manager](https://swift.org/package-manager/).

### CocoaPods
Add the following line to your Podfile:

`pod 'Harbor'` 


### Swift Package Manager
Add the following to your `Package.swift` file:

    dependencies: [
        .package(url: "https://github.com/javiermanzo/Harbor.git")
    ]

## Usage

To make a request using Harbor, you need to create a class that implements the `HServiceProtocolWithResult` protocol if you want to parse the response, or `HServiceProtocol` if the response doesn't need to be parsed.

### Service Protocol
#### HServiceProtocol
```swift
class MyRequest: HServiceProtocol {
    
    var url: String = "YOUR_URL/{PATH_PARAM}"
    var httpMethod: HHttpMethod = .post
    var headers: [String : String]?
    var queryParameters: [String : String]? = nil
    var pathParameters: [String : String]? = nil
    var body: [String : Any]? = nil
    var needAuth: Bool = true
    var timeout: TimeInterval = 5
    
    init() {
        self.pathParameters = [
            "PATH_PARAM" : "value"
        ]
        
        self.body = [
            "bodyParameter" : "value"
        ]
        
        self.headers = [
            "header" : "value"
        ]
    }
}
```

#### HServiceProtocolWithResult
```swift
class MyRequestWithResult: HServiceProtocolWithResult {
    
    typealias T = MyModel
    var url: String = "YOUR_URL/{PATH_PARAM}"
    var httpMethod: HHttpMethod = .get
    var headers: [String : String]?
    var queryParameters: [String : String]? = nil
    var pathParameters: [String : String]? = nil
    var body: [String : Any]? = nil
    var needAuth: Bool = true
    var timeout: TimeInterval = 5
    
    init() {
        self.pathParameters = [
            "PATH_PARAM" : "value"
        ]
        
        self.queryParameters = [
            "queryParameter" : "value"
        ]
        
        self.headers = [
            "header" : "value"
        ]
    }
}
```

Once the request class is created, you can execute the request using the `request` method.
```swift
Task {
     let response = await MyRequestWithResult().request()
}
```

### Response
#### HResponse
If you use `HServiceProtocol`, the result of calling `request()` will be an `HResponse` enum.
```swift
switch response {
case .success:
     break
case .cancelled:
     break
case .error(let error):
     break
}
```
#### HResponseWithResult
If you use `HServiceProtocolWithResult`, the result of calling `request()` will be an `HResponseWithResult` enum.
```swift
switch response {
case .success(let result):
     break
case .cancelled:
     break
case .error(let error):
     break
}
```
### Auth Provider
You can also implement the `HAuthProviderProtocol` protocol if you need to handle authentication. 

You `setAuthProvider` method of the `Harbor` class to set the authentication provider.

You have to create a class that implements `HAuthProviderProtocol`
```swift
class MyAuthProvider: HAuthProviderProtocol {
    func getCredentialsHeader() -> [String : String] {
        // Return the authentication headers
    }
}
```
After that, you have to set your Auth provider:

```swift 
Harbor.setAuthProvider(MyAuthProvider())
```

If the request class has the `needAuth` property set to `true`, Harbor will call the `getCredentialsHeader` method of the authentication provider to get the authentication headers before executing the request.

### Cancel Request
You can cancel the task of the request if it is running. `request()` will return `cancelled`.

```swift
let task = Task {
    let response = await MyRequestWithResult().request()
}
task.cancel()
```
## Debug

You can print debug information about your request using the `HDebugServiceProtocol` protocol. 
Implement the protocol in the request class.

```swift
class MyRequest: HServiceProtocolWithResult, HDebugServiceProtocol {
    var debugType: HDebugServiceType = .requestAndResponse
    ....
}
```
`debugType` defines what you want to print in console. The options are  `none, request, response or requestAndResponse`.

When your request is called, you will see in the Xcode console the information about your request.

## Contributing

If you run into any problems, please submit an [issue](https://github.com/javiermanzo/Harbor/issues). [Pull requests](https://github.com/javiermanzo/Harbor/pulls) are also welcome! 

## Author

Harbor was created by [Javier Manzo](https://www.linkedin.com/in/javiermanzo/).

## License

Harbor is available under the MIT license. See the  [LICENSE](https://github.com/javiermanzo/Harbor/blob/main/LICENSE.md)  file for more info.
