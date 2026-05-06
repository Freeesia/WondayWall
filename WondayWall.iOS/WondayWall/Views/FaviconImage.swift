import SwiftUI

// URLのファビコンを表示するビュー
// Google Favicon Service を利用して AsyncImage で非同期読み込みする
struct FaviconImage: View {
    let urlString: String?
    var size: CGFloat = 16

    private var faviconURL: URL? {
        guard
            let urlString,
            let pageURL = URL(string: urlString),
            let host = pageURL.host
        else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }

    var body: some View {
        AsyncImage(url: faviconURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            default:
                Image(systemName: "globe")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
