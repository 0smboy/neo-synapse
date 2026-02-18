import Foundation

final class WebSearchModule {
    private struct SearchItem {
        let title: String
        let snippet: String
        let link: String
        let source: String
    }

    private struct DuckResponse: Decodable {
        struct Topic: Decodable {
            let Text: String?
            let FirstURL: String?
            let Topics: [Topic]?
        }

        let AbstractText: String?
        let AbstractURL: String?
        let RelatedTopics: [Topic]?
    }

    func search(_ query: String) async -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return "请输入联网搜索关键词。" }

        if let items = await fetchDuckDuckGo(q), !items.isEmpty {
            return format(query: q, items: Array(items.prefix(6)))
        }
        if let items = await fetchWikipedia(q), !items.isEmpty {
            return format(query: q, items: Array(items.prefix(6)))
        }
        if let items = await fetchBingRSS(q), !items.isEmpty {
            return format(query: q, items: Array(items.prefix(6)))
        }

        return """
        # 联网搜索

        **关键词**：\(q)

        未检索到可用结果，建议换一个更具体的关键词后重试。
        """
    }

    private func format(query: String, items: [SearchItem]) -> String {
        let rows = items.enumerated().map { idx, item in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = item.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeSnippet = snippet.isEmpty ? "（无摘要）" : snippet
            return """
            \(idx + 1). **\(title)**
               \(safeSnippet)
               \(item.link)
               来源：\(item.source)
            """
        }

        return """
        # 联网搜索

        **关键词**：\(query)

        \(rows.joined(separator: "\n\n"))
        """
    }

    private func fetchDuckDuckGo(_ query: String) async -> [SearchItem]? {
        guard var components = URLComponents(string: "https://api.duckduckgo.com/") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1"),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await request(url: url)
            guard isSuccess(response) else { return nil }
            let payload = try JSONDecoder().decode(DuckResponse.self, from: data)

            var items: [SearchItem] = []
            if let abstract = payload.AbstractText, !abstract.isEmpty {
                items.append(
                    SearchItem(
                        title: query,
                        snippet: abstract,
                        link: payload.AbstractURL ?? "",
                        source: "DuckDuckGo"
                    )
                )
            }

            let flattened = flatten(payload.RelatedTopics ?? [])
            for topic in flattened {
                guard let text = topic.Text, !text.isEmpty,
                      let link = topic.FirstURL, !link.isEmpty else { continue }
                let parts = text.split(separator: " - ", maxSplits: 1).map(String.init)
                let title = parts.first ?? text
                let snippet = parts.count > 1 ? parts[1] : text
                items.append(
                    SearchItem(title: title, snippet: snippet, link: link, source: "DuckDuckGo")
                )
            }
            return items
        } catch {
            return nil
        }
    }

    private func fetchWikipedia(_ query: String) async -> [SearchItem]? {
        guard var components = URLComponents(string: "https://zh.wikipedia.org/w/api.php") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: "6"),
            URLQueryItem(name: "namespace", value: "0"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await request(url: url)
            guard isSuccess(response),
                  let array = try JSONSerialization.jsonObject(with: data) as? [Any],
                  array.count >= 4,
                  let titles = array[1] as? [String],
                  let snippets = array[2] as? [String],
                  let links = array[3] as? [String] else {
                return nil
            }

            var items: [SearchItem] = []
            for i in 0..<min(titles.count, min(snippets.count, links.count)) {
                let title = titles[i].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                items.append(
                    SearchItem(
                        title: title,
                        snippet: snippets[i],
                        link: links[i],
                        source: "Wikipedia"
                    )
                )
            }
            return items
        } catch {
            return nil
        }
    }

    private func fetchBingRSS(_ query: String) async -> [SearchItem]? {
        guard var components = URLComponents(string: "https://www.bing.com/search") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "rss"),
            URLQueryItem(name: "setlang", value: "zh-Hans"),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await request(url: url)
            guard isSuccess(response) else { return nil }

            let parser = RSSParser()
            guard let items = parser.parse(data: data), !items.isEmpty else { return nil }
            return items.map {
                SearchItem(title: $0.title, snippet: $0.description, link: $0.link, source: "Bing")
            }
        } catch {
            return nil
        }
    }

    private func request(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Synapse/1.0", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request)
    }

    private func isSuccess(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    private func flatten(_ topics: [DuckResponse.Topic]) -> [DuckResponse.Topic] {
        var list: [DuckResponse.Topic] = []
        for topic in topics {
            if let children = topic.Topics, !children.isEmpty {
                list.append(contentsOf: flatten(children))
            } else {
                list.append(topic)
            }
        }
        return list
    }
}

private final class RSSParser: NSObject, XMLParserDelegate {
    struct Item {
        let title: String
        let link: String
        let description: String
    }

    private var items: [Item] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var insideItem = false

    func parse(data: Data) -> [Item]? {
        items.removeAll()
        currentElement = ""
        currentTitle = ""
        currentLink = ""
        currentDescription = ""
        insideItem = false

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        case "description":
            currentDescription += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            insideItem = false
            let title = htmlDecoded(currentTitle).trimmingCharacters(in: .whitespacesAndNewlines)
            let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = htmlDecoded(currentDescription).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !link.isEmpty {
                items.append(Item(title: title, link: link, description: stripTags(description)))
            }
        }
    }

    private func htmlDecoded(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return text }
        if let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        ) {
            return attributed.string
        }
        return text
    }

    private func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

