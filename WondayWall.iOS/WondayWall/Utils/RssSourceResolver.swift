import Foundation
import SwiftSoup

// サイト URL または RSS URL から、実際に登録する RSS/Atom フィード URL を解決する
enum RssSourceResolver {
    static func resolve(from sourceURL: String) async -> String? {
        guard let url = URL(string: sourceURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        if isLikelyRssURL(url) {
            return sourceURL
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(
            "WondayWall/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(html, url.absoluteString),
              let linkElements = try? doc.select("link[rel][type][href]") else {
            return nil
        }

        for link in linkElements.array() {
            guard let rel = try? link.attr("rel"),
                  containsToken(rel, token: "alternate") else { continue }
            guard let type = try? link.attr("type"),
                  isFeedContentType(type) else { continue }

            if let absoluteHref = try? link.attr("abs:href"), !absoluteHref.isEmpty {
                return absoluteHref
            }

            guard let href = try? link.attr("href"), !href.isEmpty else { continue }
            if let resolvedURL = URL(string: href, relativeTo: url)?.absoluteURL.absoluteString {
                return resolvedURL
            }
        }

        return nil
    }

    static func isSupportedAbsoluteURL(_ sourceURL: String) -> Bool {
        guard let url = URL(string: sourceURL),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    private static func containsToken(_ source: String, token: String) -> Bool {
        source.components(separatedBy: .whitespacesAndNewlines)
            .contains { $0.caseInsensitiveCompare(token) == .orderedSame }
    }

    private static func isFeedContentType(_ type: String) -> Bool {
        type.localizedCaseInsensitiveContains("application/rss+xml")
            || type.localizedCaseInsensitiveContains("application/atom+xml")
    }

    private static func isLikelyRssURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.hasSuffix(".xml")
            || path.hasSuffix(".rss")
            || path.hasSuffix(".atom") {
            return true
        }

        let query = (url.query ?? "").lowercased()
        return path.contains("feed")
            || path.contains("rss")
            || path.contains("atom")
            || query.contains("feed")
            || query.contains("rss")
            || query.contains("atom")
    }
}
