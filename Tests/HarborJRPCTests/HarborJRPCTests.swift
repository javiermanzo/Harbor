import XCTest
@testable import HarborJRPC

final class HarborJRPCTests: XCTestCase {

    override class func setUp() {
        HarborJRPC.setURL("https://rpc.ankr.com/eth")
    }

    func testRequestSuccess() async throws {
        let request = TestRequest(method: "eth_blockNumber")

        let response = await request.request()
        switch response {
        case .success(let result):
            print(result)
            XCTAssertNotNil(result)
        case .error(let error):
            XCTFail("Request failed with error: \(error)")
        case .cancelled:
            XCTFail("Request was cancelled")
        }
    }

    func testRequestWrongMethod() async throws {
        let request = TestRequest(method: "wrong_method")

        let response = await request.request()
        switch response {
        case .success(let result):
            XCTFail("Request should fail")
        case .error(let error):
            switch error {
            case .jrpcError(let error):
                print(error)
                return
            default:
                XCTFail("Request failed with jrpcError: \(error)")
            }
        case .cancelled:
            XCTFail("Request was cancelled")
        }
    }
}

struct TestRequest: HJRPCRequestProtocol {
    typealias Model = String
    var method: String = "eth_blockNumber"
    var needsAuth: Bool = false
    var headers: [String : String]? = nil
    var parameters: [String : Any]? = nil

    init(method: String, parameters: [String : Any]? = nil) {
        self.method = method
        self.parameters = parameters
    }}

