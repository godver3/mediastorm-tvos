#if os(iOS)
import Foundation

/// A small element tree over `XMLParser`, namespace prefixes dropped: enough for UPnP device
/// descriptions and SOAP replies.
final class XMLTree: NSObject, XMLParserDelegate {
    final class Node {
        let name: String
        var text = ""
        var children: [Node] = []

        init(name: String) { self.name = name }

        func child(_ name: String) -> Node? { children.first { $0.name == name } }

        /// Every element under this one with `name`, depth first.
        func descendants(_ name: String) -> [Node] {
            children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
        }
    }

    private let root = Node(name: "#document")
    private var stack: [Node] = []

    static func parse(_ data: Data) -> Node? {
        let tree = XMLTree()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = tree
        return parser.parse() ? tree.root : nil
    }

    func parserDidStartDocument(_ parser: XMLParser) { stack = [root] }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = Node(name: elementName)
        stack.last?.children.append(node)
        stack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if stack.count > 1 { stack.removeLast() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
}

/// UPnP control over SOAP (`POST` to a service's control URL).
enum DLNASOAP {
    /// LG webOS takes well over ten seconds to answer a Stop once wedged, and Play on a large
    /// file can take as long while the renderer opens it (the Expo bridge allows 30 s too).
    static let timeout: TimeInterval = 30

    /// Calls `action` and returns the action's response element (`<u:ActionResponse>`).
    @discardableResult
    static func call(_ service: DLNARenderer.Service, _ action: String, _ arguments: [(String, String)],
                     timeout: TimeInterval = timeout) async throws -> XMLTree.Node {
        var body = "<?xml version=\"1.0\" encoding=\"utf-8\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
            + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:\(action) xmlns:u=\"\(escape(service.type))\">"
        for (name, value) in arguments { body += "<\(name)>\(escape(value))</\(name)>" }
        body += "</u:\(action)></s:Body></s:Envelope>"

        var request = URLRequest(url: service.controlURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.type)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.setValue("MediaStorm/1.0 UPnP/1.0 DLNADOC/1.50", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let tree = XMLTree.parse(data)
        if status != 200 {
            // A UPnP fault: 500 with `<UPnPError><errorCode>…`.
            let error = tree?.descendants("UPnPError").first
            let code = error?.child("errorCode")?.text.castTrimmed ?? "HTTP \(status)"
            let detail = error?.child("errorDescription")?.text.castTrimmed ?? ""
            throw CastError(String(localized: "The TV rejected \(action) (\(code)\(detail.isEmpty ? "" : ": \(detail)"))."))
        }
        return tree?.descendants("\(action)Response").first ?? XMLTree.Node(name: "\(action)Response")
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// UPnP clock (`H+:MM:SS[.F]`) to seconds; "NOT_IMPLEMENTED" or empty reads as unknown.
    static func seconds(_ clock: String?) -> Double? {
        let parts = (clock ?? "").split(separator: ".").first?.split(separator: ":").compactMap { Double($0) } ?? []
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", whole / 3600, whole % 3600 / 60, whole % 60)
    }
}
extension String {
    /// Whitespace and newlines trimmed (XML text, typed addresses).
    var castTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
#endif
