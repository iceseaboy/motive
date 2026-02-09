import Testing
import Foundation
@testable import Motive

struct OpenCodeAPIClientTests {

    // MARK: - PermissionReply Wire Values

    @Test func permissionReplyOnceWireValue() async throws {
        let reply = OpenCodeAPIClient.PermissionReply.once
        #expect(reply.wireValue == "once")
    }

    @Test func permissionReplyAlwaysWireValue() async throws {
        let reply = OpenCodeAPIClient.PermissionReply.always
        #expect(reply.wireValue == "always")
    }

    @Test func permissionReplyRejectWireValue() async throws {
        let reply = OpenCodeAPIClient.PermissionReply.reject(nil)
        #expect(reply.wireValue == "reject")
    }

    @Test func permissionReplyRejectWithMessageWireValue() async throws {
        let reply = OpenCodeAPIClient.PermissionReply.reject("Not allowed")
        #expect(reply.wireValue == "reject")
    }

    // MARK: - API Error Descriptions

    @Test func apiErrorNoBaseURLDescription() async throws {
        let error = OpenCodeAPIClient.APIError.noBaseURL
        #expect(error.errorDescription?.contains("no base URL") == true)
    }

    @Test func apiErrorHTTPErrorDescription() async throws {
        let error = OpenCodeAPIClient.APIError.httpError(statusCode: 404, body: "Not Found")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("404"))
        #expect(desc.contains("Not Found"))
    }

    @Test func apiErrorHTTPErrorWithoutBody() async throws {
        let error = OpenCodeAPIClient.APIError.httpError(statusCode: 500, body: nil)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("500"))
    }

    @Test func apiErrorDecodingDescription() async throws {
        let error = OpenCodeAPIClient.APIError.decodingError("Missing field")
        #expect(error.errorDescription?.contains("Missing field") == true)
    }

    @Test func apiErrorNetworkDescription() async throws {
        let underlyingError = NSError(domain: "test", code: -1009, userInfo: [NSLocalizedDescriptionKey: "No internet"])
        let error = OpenCodeAPIClient.APIError.networkError(underlyingError)
        #expect(error.errorDescription?.contains("No internet") == true)
    }

    // MARK: - Client Initial State

    @Test func clientStartsWithNoBaseURL() async throws {
        let client = OpenCodeAPIClient()
        // Attempting to create a session without a base URL should throw noBaseURL
        do {
            _ = try await client.createSession()
            Issue.record("Expected noBaseURL error")
        } catch let error as OpenCodeAPIClient.APIError {
            guard case .noBaseURL = error else {
                Issue.record("Expected noBaseURL, got \(error)")
                return
            }
        }
    }

    // MARK: - Session Info

    @Test func sessionInfoStoresIdAndTitle() async throws {
        let info = OpenCodeAPIClient.SessionInfo(id: "sess-123", title: "Test Session")
        #expect(info.id == "sess-123")
        #expect(info.title == "Test Session")
    }

    @Test func sessionInfoWithNilTitle() async throws {
        let info = OpenCodeAPIClient.SessionInfo(id: "sess-456", title: nil)
        #expect(info.id == "sess-456")
        #expect(info.title == nil)
    }
}
