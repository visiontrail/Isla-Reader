//
//  NotionAPIClientTests.swift
//  LanReadTests
//

import Foundation
import Testing
@testable import LanRead

struct NotionAPIClientTests {
    @Test
    func queryDatabaseBuildsExpectedRequest() async throws {
        let databaseID = "db_123"
        let filter: Object = [
            "property": .string("Book ID"),
            "rich_text": .object([
                "equals": .string("book_abc")
            ])
        ]

        let session = makeMockSession()
        let requestCapture = RequestCapture()
        MockURLProtocol.removeAllHandlers()
        defer { MockURLProtocol.removeAllHandlers() }

        MockURLProtocol.registerHandler(for: "/v1/databases/\(databaseID)/query") { request in
            requestCapture.set(request)

            let responseBody: Object = [
                "object": .string("list"),
                "results": .array([]),
                "has_more": .bool(false)
            ]
            let data = try JSONEncoder().encode(responseBody)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let client = NotionAPIClient(
            session: session,
            tokenProvider: StubTokenProvider(token: "test_token"),
            notificationCenter: NotificationCenter()
        )

        let result = try await client.queryDatabase(databaseId: databaseID, filter: filter)
        #expect(result["object"] == .string("list"))

        let capturedRequest = try #require(requestCapture.get())
        #expect(capturedRequest.httpMethod == "POST")
        #expect(capturedRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test_token")
        #expect(capturedRequest.value(forHTTPHeaderField: "Notion-Version") == "2022-06-28")
        #expect(capturedRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let requestBody = try #require(extractBodyData(from: capturedRequest))
        let payload = try JSONDecoder().decode(Object.self, from: requestBody)
        let filterPayload = try #require(payload["filter"]?.objectValue)
        #expect(filterPayload["property"] == .string("Book ID"))
        let richText = try #require(filterPayload["rich_text"]?.objectValue)
        #expect(richText["equals"] == .string("book_abc"))
    }

    @Test
    func appendBlockChildrenPropagatesRetryAfterOn429() async throws {
        let blockID = "block_456"
        let children: [Block] = [[
            "object": .string("block"),
            "type": .string("paragraph"),
            "paragraph": .object([
                "rich_text": .array([
                    .object([
                        "type": .string("text"),
                        "text": .object([
                            "content": .string("Hello Notion")
                        ])
                    ])
                ])
            ])
        ]]

        let session = makeMockSession()
        let requestCapture = RequestCapture()
        MockURLProtocol.removeAllHandlers()
        defer { MockURLProtocol.removeAllHandlers() }

        MockURLProtocol.registerHandler(for: "/v1/blocks/\(blockID)/children") { request in
            requestCapture.set(request)

            let responseBody: Object = [
                "object": .string("error"),
                "message": .string("rate_limited")
            ]
            let data = try JSONEncoder().encode(responseBody)
            let headers = ["Retry-After": "12"]
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: headers)!
            return (response, data)
        }

        let client = NotionAPIClient(
            session: session,
            tokenProvider: StubTokenProvider(token: "test_token"),
            notificationCenter: NotificationCenter()
        )

        do {
            _ = try await client.appendBlockChildren(blockId: blockID, children: children)
            Issue.record("Expected NotionAPIError.rateLimited")
        } catch let error as NotionAPIError {
            guard case .rateLimited(let retryAfter) = error else {
                Issue.record("Unexpected NotionAPIError: \(error)")
                return
            }
            #expect(retryAfter == 12)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let capturedRequest = try #require(requestCapture.get())
        #expect(capturedRequest.httpMethod == "PATCH")
        #expect(capturedRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test_token")
        #expect(capturedRequest.value(forHTTPHeaderField: "Notion-Version") == "2022-06-28")

        let requestBody = try #require(extractBodyData(from: capturedRequest))
        let payload = try JSONDecoder().decode(Object.self, from: requestBody)
        let payloadChildren = try #require(payload["children"])
        guard case .array(let items) = payloadChildren else {
            Issue.record("children should be an array")
            return
        }
        #expect(items.count == 1)
    }
}

private extension NotionAPIClientTests {
    func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func extractBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }

        return data.isEmpty ? nil : data
    }
}

private struct StubTokenProvider: NotionAccessTokenProviding {
    let token: String?

    func accessToken() throws -> String? {
        token
    }
}

private final class RequestCapture {
    private let queue = DispatchQueue(label: "NotionAPIClientTests.requestCapture")
    private var request: URLRequest?

    func set(_ request: URLRequest) {
        queue.sync {
            self.request = request
        }
    }

    func get() -> URLRequest? {
        queue.sync {
            request
        }
    }
}

private final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static var handlers: [String: Handler] = [:]
    private static let lockQueue = DispatchQueue(label: "MockURLProtocol.handlers")

    static func registerHandler(for path: String, handler: @escaping Handler) {
        lockQueue.sync {
            handlers[path] = handler
        }
    }

    static func removeAllHandlers() {
        lockQueue.sync {
            handlers.removeAll()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let path = request.url?.path else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let handler = Self.lockQueue.sync {
            Self.handlers[path]
        }

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
