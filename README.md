
<p align="center" width="100%">
    <img width="40%" src="https://raw.githubusercontent.com/javiermanzo/Harbor/main/Resources/Harbor.png"> 
</p>

![Release](https://img.shields.io/github/v/release/javiermanzo/Harbor?style=flat-square)
![CI](https://img.shields.io/github/actions/workflow/status/javiermanzo/Harbor/swift.yml?style=flat-square)
[![Swift](https://img.shields.io/badge/Swift-5.9_6.0-orange?style=flat-square)](https://img.shields.io/badge/Swift-5.9_5.10_6.0-Orange?style=flat-square)
[![Platforms](https://img.shields.io/badge/Platforms-macOS_iOS-yellowgreen?style=flat-square)](https://img.shields.io/badge/Platforms-macOS_iOS_tvOS_watchOS_vision_OS_Linux_Windows_Android-Green?style=flat-square) 
![Swift Package Manager(https://swiftpackageindex.com/javiermanzo/Harbor)](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)
![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Harbor.svg?style=flat-square)

Harbor is a library for making API requests in Swift in a simple way using async/await.

## Table of Contents
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
  - [CocoaPods](#cocoapods)
  - [Swift Package Manager](#swift-package-manager)
- [Usage](#usage)
  - [Configuration](#configuration)
    - [Default Headers](#default-headers)
    - [Auth Provider](#auth-provider)
    - [Custom URLSession](#custom-urlsession)
    - [mTLS Support](#mtls-support)
    - [SSL Pinning](#ssl-pinning)
  - [Request Protocols](#request-protocols)
    - [HGetRequestProtocol](#hgetrequestprotocol)
    - [HPostRequestProtocol](#hpostrequestprotocol)
    - [HPatchRequestProtocol](#hpatchrequestprotocol)
    - [HPutRequestProtocol](#hputrequestprotocol)
    - [HDeleteRequestProtocol](#hdeleterequestprotocol)
    - [HRequestWithResultProtocol](#hrequestwithresultprotocol)
  - [Request Calling](#request-calling)
  - [Response](#response)
    - [HResponse](#hresponse)
    - [HResponseWithResult](#hresponsewithresult)
  - [Cancel Request](#cancel-request)
  - [Debug](#debug)
  - [JSON RPC](#json-rpc)
    - [Installation](#installation-1)
    - [Configuration](#configuration-1)
      - [Set URL](#set-url)
      - [Set JSON RPC Version](#set-json-rpc-version)
    - [Request Protocol](#request-protocol)
      - [HJRPCRequestProtocol](#hjrpcrequestprotocol)
    - [Response](#response-1)
- [Mocks](#mocks)
- [Contributing](#contributing)
- [Author](#author)
- [License](#license)

## Features

- [x] Rest Requests
- [x] JSON RPC Requests
- [x] Auth provider handler
- [x] Multipart Post Requests
- [x] Retry Requests
- [x] Cancel Request
- [x] Debug Requests
- [x] cURL Command Output
- [x] Default Headers
- [x] Custom URLSession
- [x] mTLS Certificate
- [x] SSL Pinning
- [x] Swift 6 Compatible
- [x] Mock Requests

## Requirements

- Swift 5.9+
- iOS 15.0

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

### Configuration
This provides a centralized way to manage common configuration.

#### Default Headers
You can include default headers in every request.

To configure the default headers:

```swift
await Harbor.setDefaultHeaderParameters([
    "MY_CUSTOM_HEADER": "VALUE"
])
```

#### Auth Provider
You can implement the `HAuthProviderProtocol` if you need to handle authentication. Use the `setAuthProvider` method of the `Harbor` class to set the authentication provider.

You need to create a class that implements `HAuthProviderProtocol`:

```swift
class MyAuthProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader {
        // Return a HAuthorizationHeader instance
    }
    
    func authFailed() async {
        // This method is called when the request receives a 401 status code
    }
}
```

After that, set your Auth provider:

```swift
await Harbor.setAuthProvider(MyAuthProvider())
```

If the request class has the `needsAuth` property set to `true`, Harbor will call the `getAuthorizationHeader` method of the authentication provider to get the `HAuthorizationHeader` instance to set it in the header before executing the request.

#### Custom URLSession
Harbor allows you to set a custom `URLSession` for your requests, providing flexibility for advanced configurations such as custom caching, timeout settings, or additional protocols.

To set a custom `URLSession`, use the `setCustomURLSession` method:

```swift
let customSession = URLSession(configuration: .default)
await Harbor.setCustomURLSession(customSession)
```

#### mTLS Support
Harbor supports mutual TLS (mTLS) for enhanced security in API requests. This feature allows clients to present certificates to the server, ensuring both the client and server authenticate each other.

To set up mTLS, use the `setMTLS` method:

```swift
let mTLS = HmTLS(p12FileUrl: yourP12FileUrl, password: "yourPassword")
await Harbor.setMTLS(mTLS)
```

#### SSL Pinning
Harbor supports SSL Pinning to enhance the security of your API requests. SSL Pinning ensures that the client checks the server's certificate against a known pinned certificate, adding an additional layer of security.

To configure SSL Pinning, use the `setSSlPinningSHA256` method:

```swift
let sslPinningSHA256 = "yourSHA256CertificateHash"
await Harbor.setSSlPinningSHA256(sslPinningSHA256)
```

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
- `bodyType`: Specifies the type of data being sent in the body of the request. It can be either json or multipart.

#### HPatchRequestProtocol
Use the `HPatchRequestProtocol` protocol if you want to send a PATCH request.

##### Extra Properties:
- `bodyParameters`: A dictionary of parameters that will be included in the body of the request.
- `bodyType`: Specifies the type of data being sent in the body of the request. It can be either json or multipart.

#### HPutRequestProtocol
Use the `HPutRequestProtocol` protocol if you want to send a PUT request.

##### Extra Properties:
- `bodyParameters`: A dictionary of parameters that will be included in the body of the request.
- `bodyType`: Specifies the type of data being sent in the body of the request. It can be either json or multipart.

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
case .error(let error):
    break
}
```

### Cancel Request
You can cancel the task of the request if it is running. `request()` will return `cancelled` as an error case.

```swift
let task = Task {
    let response = await MyRequestWithResult().request()
}
task.cancel()
```

### Debug
You can print debug information about your request using the `HDebugRequestProtocol` protocol. Implement the protocol in the request class.

```swift
class MyRequest: HRequestWithResultProtocol, HDebugRequestProtocol {
    var debugType: HDebugRequestType = .requestAndResponse
    
    // ...
}
```

`debugType` defines what you want to print in the console. The options are `none`, `request`, `response`, or `requestAndResponse`.

When your request is called, you will see in the Xcode console the information about your request.


## JSON RPC
Harbor also supports JSON RPC via the `HarborJRPC` package.

### Installation
To use HarborJRPC, add the following import to your file:

```swift
import HarborJRPC
```

### Configuration

#### Set URL
Use this method to set the URL for the JSON RPC requests:

```swift
HarborJRPC.setURL("https://api.example.com/")
```

#### Set JSON RPC Version
Use this method to set the JSON RPC version:

```swift
// It uses 2.0 as default 
HarborJRPC.setJRPCVersion("2.0")
```
### Request Protocol

#### HJRPCRequestProtocol
Use the `HJRPCRequestProtocol` protocol if you want to send a JRPC request.

##### Properties:
- `Model`: The model that conforms to the `Codable` protocol, representing the expected response structure.
- `method`: A string that represents the JRPC method to be called.
- `needsAuth`: A boolean indicating whether the request requires authentication.
- `retries`: The number of retries in case the request fails.
- `headers`: An optional dictionary containing any additional headers to be included in the request.
- `parameters`: An optional dictionary of parameters to be included in the request.

### Response
To configure a request using HarborJRPC, create a struct or class that implements `HJRPCRequestProtocol`. The result of calling `request()` will be an `HJRPCResponse`:

```swift
switch response {
case .success(let result):
    break
case .error(let error):
    break
}
```

## Mocks
Harbor allows you to register and manage mocks to facilitate testing your API requests.

### HMock
Use `HMock` to declare mock responses for your requests.

#### Properties:
- `request`: The request type that conforms to `HRequestBaseRequestProtocol` for which the mock is being set.
- `statusCode`: The HTTP status code to return.
- `jsonResponse`: A `String` representing the JSON response. This will be decoded as the expected model for your request.
- `error`: An optional `HRequestError` if you want to simulate an error response.
- `delay`: An optional delay (in seconds) before returning the mock response, to simulate network latency.

### Register a Mock
To register a mock, use the `register(mock:)` method. This will allow you to simulate responses instead of making actual API calls.

```swift
let mock = HMock(
    ///
)
await Harbor.register(mock: mock)
```

### Registering a Success Mock

```swift
let jsonResponse = """
    { "name": "John Doe" }
"""
let mock = HMock(
    request: MyGetUsersRequest.self,
    statusCode: 200,
    jsonResponse: jsonResponse
)
await Harbor.register(mock: mock)
```

### Registering a Error Mock

```swift
let mock = HMock(
    request: MyGetUsersRequest.self,
    statusCode: 401,
    error: .authNeeded
)
await Harbor.register(mock: mock)
```

### Using Mocks Only in Debug Mode
You can configure mocks to only be used in #DEBUG, preventing them from affecting production environments. The default value is *true*.

```swift
await Harbor.setMocksOnlyInDebug(false)
```

### Removing a Specific Mock
If you need to remove a specific mock, use the `remove(mock:)` method.

```swift
await Harbor.remove(mock: mock)
```

### Removing All Mocks
To clear all registered mocks, use the `removeAllMocks()` method.

```swift
await Harbor.removeAllMocks()
```

### Complete Example
Below is a complete example demonstrating how to set up and use mocks with Harbor:

```swift

Task {
    let jsonResponse = """
        { "users": [{ "id": 1, "name": "Alice" }] }
    """
    let userMock = HMock(
        request: MyGetUsersRequest.self,
        statusCode: 200,
        jsonResponse: jsonResponse
    )

    // Register the mock
    await Harbor.register(mock: userMock)

    // Perform a request that will use the registered mock
    let response = await MyGetUsersRequest().request()
    switch response {
    case .success(let users):
        // You will receive the mocked response here
        print("Users:", users)
    case .error(let error):
        break
    }
}
```

## Contributing
If you run into any problems, please submit an [issue](https://github.com/javiermanzo/Harbor/issues). [Pull requests](https://github.com/javiermanzo/Harbor/pulls) are also welcome! 

## Author
Harbor was created by [Javier Manzo](https://www.linkedin.com/in/javiermanzo/).

## License
Harbor is available under the MIT license. See the [LICENSE](https://github.com/javiermanzo/Harbor/blob/main/LICENSE.md) file for more info.

