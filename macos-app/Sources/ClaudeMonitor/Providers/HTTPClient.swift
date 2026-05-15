import Foundation

struct HTTPResponse {
    let status: Int
    let data: Data

    var ok: Bool { (200..<300).contains(status) }

    func jsonObject() throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            throw NSError(domain: "HTTPClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected JSON object"])
        }
        return dict
    }
}

enum HTTPClient {
    static func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(status: status, data: data)
    }

    static func postForm(_ url: URL, fields: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")

        var comps = URLComponents()
        comps.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw NSError(domain: "HTTPClient", code: status, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
        }
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            throw NSError(domain: "HTTPClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected JSON object"])
        }
        return dict
    }
}
