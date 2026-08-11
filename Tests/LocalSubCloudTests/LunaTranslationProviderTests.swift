import Foundation
import XCTest
@testable import LocalSubCloud
import LocalSubCore

final class LunaTranslationProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testSendsTextOnlyStructuredRequestAndCorrelatesResponses() async throws {
        let session = makeSession()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = try request.bodyData()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "gpt-5.6-luna")
            XCTAssertEqual(json["store"] as? Bool, false)
            XCTAssertNil(json["audio"])
            let text = try XCTUnwrap(json["text"] as? [String: Any])
            let format = try XCTUnwrap(text["format"] as? [String: Any])
            XCTAssertEqual(format["type"] as? String, "json_schema")
            XCTAssertEqual(format["strict"] as? Bool, true)
            let response = """
            {"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\\"translations\\":[{\\"id\\":\\"unit-1\\",\\"japanese\\":\\"始めましょう。\\"},{\\"id\\":\\"unit-0\\",\\"japanese\\":\\"最初のマネージドエージェントを提供します。\\"}]}"}]}]}
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(response.utf8))
        }
        let provider = LunaTranslationProvider(apiKey: "test-key", session: session)
        let requests = [
            TranslationRequest(id: "unit-0", sourceSpanIDs: ["segment-0"], text: "Ship your first Managed Agent."),
            TranslationRequest(id: "unit-1", sourceSpanIDs: ["segment-1"], text: "Let's get started."),
        ]

        let responses = try await provider.translate(
            requests,
            glossary: [.init(source: "Managed Agent", target: "マネージドエージェント")]
        )

        XCTAssertEqual(responses.map(\.requestID), ["unit-1", "unit-0"])
        XCTAssertEqual(try TranslationCorrelator.correlate(requests: requests, responses: responses).map(\.text), [
            "最初のマネージドエージェントを提供します。", "始めましょう。",
        ])
    }

    func testRejectsHTTPFailureIncompleteResponseAndInvalidBatch() async throws {
        let session = makeSession()
        let request = TranslationRequest(id: "unit-0", sourceSpanIDs: ["segment-0"], text: "Hello")
        let provider = LunaTranslationProvider(apiKey: "test-key", session: session)

        MockURLProtocol.handler = { request in
            let response = #"{"error":{"code":"model_not_found","message":"project detail","type":"invalid_request_error"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data(response.utf8))
        }
        do {
            _ = try await provider.translate([request])
            XCTFail("Expected model access error")
        } catch {
            XCTAssertEqual(error as? LunaTranslationError, .modelUnavailable)
        }

        MockURLProtocol.handler = { request in
            let response = #"{"status":"incomplete","output":[]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(response.utf8))
        }
        await XCTAssertThrowsAsync(try await provider.translate([request]))

        MockURLProtocol.handler = { request in
            let response = #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"translations\":[{\"id\":\"other\",\"japanese\":\"こんにちは\"}]}"}]}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(response.utf8))
        }
        await XCTAssertThrowsAsync(try await provider.translate([request]))
    }

    func testRejectsJobResourceLimitBeforeStartingAnyRequest() async {
        let session = makeSession()
        MockURLProtocol.handler = { _ in
            XCTFail("A rejected job must not start a network request")
            throw URLError(.cancelled)
        }
        let requests = (0...1_000).map {
            TranslationRequest(id: "unit-\($0)", sourceSpanIDs: ["segment-\($0)"], text: "Hello")
        }

        do {
            _ = try await LunaTranslationProvider(apiKey: "test-key", session: session).translate(requests)
            XCTFail("Expected resource limit")
        } catch {
            XCTAssertEqual(error as? LunaTranslationError, .resourceLimit)
        }
    }

    func testRejectsDirectOversizedGlossaryBeforeStartingAnyRequest() async {
        let session = makeSession()
        MockURLProtocol.handler = { _ in
            XCTFail("A rejected glossary must not start a network request")
            throw URLError(.cancelled)
        }
        let request = TranslationRequest(id: "unit-0", sourceSpanIDs: ["segment-0"], text: "Hello")
        let glossary = (0..<100).map {
            GlossaryEntry(
                source: "\($0)-" + String(repeating: "語", count: 115),
                target: String(repeating: "訳", count: 16)
            )
        }

        do {
            _ = try await LunaTranslationProvider(apiKey: "test-key", session: session)
                .translate([request], glossary: glossary)
            XCTFail("Expected resource limit")
        } catch {
            XCTAssertEqual(error as? LunaTranslationError, .resourceLimit)
        }
    }

    func testRejectsDirectGlossaryTargetThatCannotFitCaption() async {
        let session = makeSession()
        MockURLProtocol.handler = { _ in
            XCTFail("An invalid glossary must not start a network request")
            throw URLError(.cancelled)
        }
        let request = TranslationRequest(id: "unit-0", sourceSpanIDs: ["segment-0"], text: "Hello")
        let glossary = [GlossaryEntry(source: "term", target: String(repeating: "語", count: 25))]

        do {
            _ = try await LunaTranslationProvider(apiKey: "test-key", session: session)
                .translate([request], glossary: glossary)
            XCTFail("Expected invalid glossary")
        } catch {
            XCTAssertEqual(error as? LunaTranslationError, .invalidRequest("invalid glossary entry"))
        }
    }

    func testTranslatesMultipleBatchesAndKeepsAllIDs() async throws {
        let session = makeSession()
        let lock = NSLock()
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.handler = { request in
            let body = try request.bodyData()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let input = try XCTUnwrap(json["input"] as? String)
            let inputData = try XCTUnwrap(input.data(using: .utf8))
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: inputData) as? [String: Any])
            let units = try XCTUnwrap(payload["units"] as? [[String: String]])
            let translations = units.map { ["id": $0["id"]!, "japanese": "訳\($0["id"]!)"] }
            let translatedData = try JSONSerialization.data(withJSONObject: ["translations": translations])
            let translatedText = String(decoding: translatedData, as: UTF8.self)
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            lock.withLock { requestCount += 1 }
            let response = "{\"status\":\"completed\",\"output\":[{\"content\":[{\"type\":\"output_text\",\"text\":\"\(translatedText)\"}]}]}"
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(response.utf8))
        }
        let requests = (0..<41).map {
            TranslationRequest(id: "unit-\($0)", sourceSpanIDs: ["segment-\($0)"], text: "Hello")
        }

        let responses = try await LunaTranslationProvider(apiKey: "test-key", session: session).translate(requests)

        XCTAssertEqual(responses.count, 41)
        let finalRequestCount = lock.withLock { requestCount }
        XCTAssertEqual(finalRequestCount, 2)
    }

    func testStopsStreamingResponseAtSizeLimit() async {
        let session = makeSession()
        MockURLProtocol.handler = { request in
            let oversized = Data(repeating: 0x20, count: 2 * 1_024 * 1_024 + 1)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, oversized)
        }
        let request = TranslationRequest(id: "unit-0", sourceSpanIDs: ["segment-0"], text: "Hello")

        do {
            _ = try await LunaTranslationProvider(apiKey: "test-key", session: session).translate([request])
            XCTFail("Expected response limit")
        } catch {
            XCTAssertEqual(error as? LunaTranslationError, .responseTooLarge)
        }
    }

    func testCancellationAfterFirstBatchStartsNoSecondBatch() async {
        let session = makeSession()
        let firstRequestStarted = expectation(description: "first request started")
        let releaseFirstResponse = DispatchSemaphore(value: 0)
        let lock = NSLock()
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.handler = { request in
            let count = lock.withLock { requestCount += 1; return requestCount }
            if count == 1 {
                firstRequestStarted.fulfill()
                _ = releaseFirstResponse.wait(timeout: .now() + 2)
            }
            return try successfulResponse(for: request)
        }
        let requests = (0..<41).map {
            TranslationRequest(id: "unit-\($0)", sourceSpanIDs: ["segment-\($0)"], text: "Hello")
        }
        let translationTask = Task {
            try await LunaTranslationProvider(apiKey: "test-key", session: session).translate(requests)
        }

        await fulfillment(of: [firstRequestStarted], timeout: 1)
        translationTask.cancel()
        releaseFirstResponse.signal()
        do {
            _ = try await translationTask.value
            XCTFail("Expected cancellation")
        } catch {}

        XCTAssertEqual(lock.withLock { requestCount }, 1)
    }

    func testDeadlineCancelsCurrentBatchAndStartsNoNextBatch() async {
        let session = makeSession()
        let lock = NSLock()
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.handler = { request in
            lock.withLock { requestCount += 1 }
            Thread.sleep(forTimeInterval: 0.1)
            return try successfulResponse(for: request)
        }
        let requests = (0..<41).map {
            TranslationRequest(id: "unit-\($0)", sourceSpanIDs: ["segment-\($0)"], text: "Hello")
        }

        do {
            _ = try await LunaTranslationProvider(
                apiKey: "test-key",
                session: session,
                jobTimeout: .milliseconds(10)
            ).translate(requests)
            XCTFail("Expected deadline")
        } catch {
            XCTAssertEqual(error as? LunaTranslationError, .deadlineExceeded)
        }
        XCTAssertEqual(lock.withLock { requestCount }, 1)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private func successfulResponse(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    let body = try request.bodyData()
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let input = try XCTUnwrap(json["input"] as? String)
    let inputData = try XCTUnwrap(input.data(using: .utf8))
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: inputData) as? [String: Any])
    let units = try XCTUnwrap(payload["units"] as? [[String: String]])
    let translations = units.map { ["id": $0["id"]!, "japanese": "訳\($0["id"]!)"] }
    let translatedData = try JSONSerialization.data(withJSONObject: ["translations": translations])
    let translatedText = String(decoding: translatedData, as: UTF8.self)
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    let response = "{\"status\":\"completed\",\"output\":[{\"content\":[{\"type\":\"output_text\",\"text\":\"\(translatedText)\"}]}]}"
    return (
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
        Data(response.utf8)
    )
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private extension URLRequest {
    func bodyData() throws -> Data {
        if let httpBody { return httpBody }
        let stream = try XCTUnwrap(httpBodyStream)
        stream.open()
        defer { stream.close() }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            output.append(buffer, count: count)
        }
        return output
    }
}

private func XCTAssertThrowsAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
