import Foundation
import CoreFoundation

enum PageTitleFetcher {
    static func fetch(_ url: URL) async -> String? {
        guard PageTitle.url(url.absoluteString) != nil else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: TitleRequestDelegate())
            guard let response = response as? HTTPURLResponse,
                (200..<300).contains(response.statusCode),
                ["text/html", "application/xhtml+xml"].contains(response.mimeType?.lowercased() ?? "")
            else { return nil }
            var data = Data()
            let encoding = response.textEncodingName.flatMap {
                let value = CFStringConvertIANACharSetNameToEncoding($0 as CFString)
                return value == kCFStringEncodingInvalidId ? nil
                    : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(value))
            } ?? .utf8
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < PageTitle.maximumBytes else { break }
                data.append(byte)
            }
            try Task.checkCancellation()
            return String(data: data, encoding: encoding).flatMap(PageTitle.parse)
        } catch { return nil }
    }
}

/// HTTP(S) redirects only; no cookies, credential lookup, or authentication prompts.
private final class TitleRequestDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var redirects = 0

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let allowed = lock.withLock { redirects += 1; return redirects <= 5 }
        completionHandler(allowed && request.url.flatMap { PageTitle.url($0.absoluteString) } != nil ? request : nil)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}
