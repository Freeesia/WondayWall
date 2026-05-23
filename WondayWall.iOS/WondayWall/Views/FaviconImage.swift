import SwiftUI

// URLのファビコンを表示するビュー
// Google Favicon Service から取得した画像をファイルキャッシュして表示する
struct FaviconImage: View {
    let urlString: String?
    var size: CGFloat = 16
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: urlString) {
            image = await FaviconCache.loadImage(for: urlString)
        }
    }
}

// ファビコンのファイルキャッシュ
private enum FaviconCache {
    private static var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func loadImage(for urlString: String?) async -> UIImage? {
        guard let host = normalizedHost(from: urlString) else { return nil }
        let cacheURL = cacheFileURL(for: host)

        if let data = try? Data(contentsOf: cacheURL), let image = UIImage(data: data) {
            return image
        }

        guard let faviconURL = faviconURL(for: host) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: faviconURL)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode),
                let image = UIImage(data: data)
            else { return nil }

            try? data.write(to: cacheURL, options: .atomic)
            return image
        } catch {
            return nil
        }
    }

    private static func normalizedHost(from urlString: String?) -> String? {
        guard
            let urlString,
            let pageURL = URL(string: urlString),
            let host = pageURL.host
        else { return nil }
        return host.lowercased()
    }

    private static func faviconURL(for host: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "64")
        ]
        return components?.url
    }

    private static func cacheFileURL(for host: String) -> URL {
        let fileName = host
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)?
            .appending(".png") ?? "favicon.png"
        return cacheDirectory.appendingPathComponent(fileName)
    }
}
