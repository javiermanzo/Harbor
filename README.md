
<p align="center" width="100%">
    <img width="40%" src="https://raw.githubusercontent.com/javiermanzo/Harbor/main/Resources/Harbor.png"> 
</p>

![Swift](https://img.shields.io/badge/Swift-5-orange?style=flat-square) ![Platforms](https://img.shields.io/badge/Platforms-iOS-yellowgreen?style=flat-square) ![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Harbor.svg?style=flat-square) ![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)

# Harbor

Harbor is a library for making API requests in Swift in a simple way using async/await.

## Requirements

- Swift 5
- iOS 13.0

## Installation

You can add Harbor to your project using [CocoaPods](https://cocoapods.org/) or [Swift Package Manager](https://swift.org/package-manager/).

### CocoaPods

Add the following line to your Podfile:

```ruby
pod 'Harbor'
```

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/javiermanzo/Harbor.git")
]
```

## Usage

### Request Protocols

To make a request using Harbor, you need to create a class that implements one of the following protocols.

#### HGetRequestProtocol
Use the `HGetRequestProtocol` protocol if you want to send a GET request.

##### Extra Properties:
- `queryParameters`: A dictionary of query parameters that will be added to the URL.
- `Model`: The result of the request will be parsed to this entity.


#### HPostRequestProtocol
Use the `HPostRequestProtocol` protocol if you want to send a POST request.

##### Extra Properties:
- `bodyParameters`: A dictionary of parameters that will be included in the body of the request.
- `bodyType`: Specifies the type of data being sent in the body of the request. It can be either `json` or `multipart`.


#### HPatchRequestProtocol
Use the `HPatchRequestProtocol` protocol if you want to send a PATCH request.

##### Extra Properties:
- `bodyParameters`: A dictionary of parameters that will be included in the body of the request.
- `bodyType`: Specifies the type of data being sent in the body of the request. It can be either `json` or `multipart`.


#### HPutRequestProtocol
Use the `HPutRequestProtocol` protocol if you want to send a PUT request.

##### Extra Properties:
- `bodyParameters`: A dictionary of parameters that will be included in the body of the request.
- `bodyType`: Specifies the type of data being sent in the body of the request. It can be either `json` or `multipart`.


#### HDeleteRequestProtocol
Use the `HDeleteRequestProtocol` protocol if you want to send a DELETE request.


#### HRequestWithResultProtocol
Use the `HRequestWithResultProtocol` protocol if you want to parse the response into a specific model. This protocol requires you to define the type of model you expect in the response.

##### Extra Properties:
- `Model`: The result of the request will be parsed to this entity.

### Request Calling
Once the request class is created, you can execute the request using the `request` method.

```swift
Task {
    let response = await MyRequestWithResult().request()
}
```

### Response

#### HResponse

If you use a protocol different from `HGetRequestProtocol` or `HRequestWithResultProtocol`, the result of calling `request()` will be an `HResponse` enum.

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

If you use `HGetRequestProtocol` or `HRequestWithResultProtocol`, the result of calling `request()` will be an `HResponseWithResult` enum.

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

You can also implement the `HAuthProviderProtocol` if you need to handle authentication. Use the `setAuthProvider` method of the `Harbor` class to set the authentication provider.

You need to create a class that implements `HAuthProviderProtocol`:

```swift
class MyAuthProvider: HAuthProviderProtocol {
    func getCredentialHeader() -> HAuthorizationHeader {
        // Return a HAuthorizationHeader instance
    }
}
```

After that, set your Auth provider:

```swift
Harbor.setAuthProvider(MyAuthProvider())
```

If the request class has the `needAuth` property set to `true`, Harbor will call the `getAuthorizationHeader` method of the authentication provider to get the `HAuthorizationHeader` instance to set it in the header before executing the request.

### Default Headers

Harbor allows you to set default headers that will be included in every request. This can be useful for adding common headers such as user agent or content types to all your API requests.

To set default headers, you can call the `setDefaultHeaders` method:

```swift
Harbor.setDefaultHeaders([
    "MY_CUSTOM_HEADER": "VALUE"
])
```

Before each request is executed, Harbor will merge the default headers with the headers specified in the request class. This ensures that all necessary headers are included in the request.

With this feature, you can manage your request headers more efficiently and ensure consistency across all your API requests.

### Cancel Request

You can cancel the task of the request if it is running. `request()` will return `cancelled`.

```swift
let task = Task {
    let response = await MyRequestWithResult().request()
}
task.cancel()
```

## Debug

You can print debug information about your request using the `HDebugRequestProtocol` protocol. Implement the protocol in the request class.

```swift
class MyRequest: HRequestWithResultProtocol, HDebugRequestProtocol {
    var debugType: HDebugRequestType = .requestAndResponse
    
    // ...
}
```

`debugType` defines what you want to print in the console. The options are `none, request, response or requestAndResponse`.

When your request is called, you will see in the Xcode console the information about your request.

## Contributing

If you run into any problems, please submit an [issue](https://github.com/javiermanzo/Harbor/issues). [Pull requests](https://github.com/javiermanzo/Harbor/pulls) are also welcome! 

## Author

Harbor was created by [Javier Manzo](https://www.linkedin.com/in/javiermanzo/).

## License

Harbor is available under the MIT license. See the [LICENSE](https://github.com/javiermanzo/Harbor/blob/main/LICENSE.md) file for more info.
