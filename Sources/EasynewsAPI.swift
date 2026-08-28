import Foundation

// MARK: - Flexible JSON

/// Easynews returns objects keyed by numeric strings ("0", "2", "10"...) and
/// occasionally changes shapes between API versions. Rather than a rigid
/// Codable struct that throws on the first surprise, we decode into this and
/// pull fields by name with fallbacks. Anything unexpected degrades to nil.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let d):
            guard d.isFinite else { return nil }
            return d == d.rounded() && abs(d) < 9e18 ? String(Int64(d)) : String(d)
        case .bool(let b): return String(b)
        default: return nil
        }
    }

    var intValue: Int64? {
        switch self {
        case .number(let d):
            guard d.isFinite, abs(d) < 9e18 else { return nil }
            return Int64(d)
        case .string(let s): return Int64(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    /// First non-empty string found among the given keys.
    func str(_ keys: String...) -> String? {
        for k in keys {
            if let v = self[k]?.stringValue, !v.isEmpty { return v }
        }
        return nil
    }

    func int(_ keys: String...) -> Int64? {
        for k in keys {
            if let v = self[k]?.intValue { return v }
        }
        return nil
    }

    func strings(_ keys: String...) -> [String] {
        for k in keys {
            if let arr = self[k]?.arrayValue {
                return arr.compactMap { $0.stringValue }
            }
            if let s = self[k]?.stringValue, !s.isEmpty {
                return s.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return []
    }
}

// MARK: - Model

struct EasynewsFile: Identifiable, Hashable {
    let id: String
    let filename: String
    let ext: String
    let sizeText: String
    let rawSize: Int64
    let runtime: String?
    let width: Int?
    let height: Int?
    let audioLanguages: [String]
    let subtitleLanguages: [String]
    let poster: String?
    let group: String?
    let rawJSON: String

    /// Human label like "1080p" derived from pixel dimensions.
    var resolutionLabel: String? {
        guard let h = height, h > 0 else { return nil }
        switch h {
        case 2000...: return "4K"
        case 1400..<2000: return "1440p"
        case 1000..<1400: return "1080p"
        case 700..<1000: return "720p"
        case 500..<700: return "576p"
        default: return "\(h)p"
        }
    }

    var sizeLabel: String {
        if rawSize > 0 {
            return ByteCountFormatter.string(fromByteCount: rawSize, countStyle: .file)
        }
        return sizeText
    }

    /// Filename without a trailing duplicate of `ext`.
    var baseName: String {
        guard !ext.isEmpty, filename.lowercased().hasSuffix(ext.lowercased()) else {
            return filename
        }
        return String(filename.dropLast(ext.count))
    }

    static func from(_ dict: [String: JSONValue]) -> EasynewsFile? {
        guard let hash = dict.str("0", "hash", "id") else { return nil }

        var ext = dict.str("2", "ext", "extension") ?? ""
        if !ext.isEmpty && !ext.hasPrefix(".") { ext = "." + ext }

        let name = dict.str("10", "subject", "filename", "fn") ?? hash

        let pretty = try? JSONSerialization.data(
            withJSONObject: JSONValueBridge.toFoundation(.object(dict)),
            options: [.prettyPrinted, .sortedKeys]
        )

        return EasynewsFile(
            id: hash,
            filename: name,
            ext: ext,
            sizeText: dict.str("4", "size") ?? "",
            rawSize: dict.int("rawSize", "rawsize", "bytes") ?? 0,
            runtime: dict.str("runtime", "duration"),
            width: dict.int("width", "w").map { Int($0) },
            height: dict.int("height", "h").map { Int($0) },
            audioLanguages: dict.strings("alangs", "audioLangs"),
            subtitleLanguages: dict.strings("slangs", "subtitleLangs"),
            poster: dict.str("11", "poster", "from"),
            group: dict.str("6", "group"),
            rawJSON: pretty.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        )
    }
}

/// Converts JSONValue back to Foundation types so we can pretty-print it for the debug view.
enum JSONValueBridge {
    static func toFoundation(_ v: JSONValue) -> Any {
        switch v {
        case .string(let s): return s
        case .number(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let a): return a.map(toFoundation)
        case .object(let o): return o.mapValues(toFoundation)
        }
    }
}

// MARK: - Search options

enum SortOption: String, CaseIterable, Identifiable {
    case relevance
    case newest
    case largest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relevance: return "Relevance"
        case .newest: return "Newest"
        case .largest: return "Largest"
        }
    }

    var systemImage: String {
        switch self {
        case .relevance: return "sparkle.magnifyingglass"
        case .newest: return "clock"
        case .largest: return "arrow.up.arrow.down"
        }
    }

    /// Easynews sort field for the primary sort key.
    fileprivate var field: String {
        switch self {
        case .relevance: return "relevance"
        case .newest: return "dtime"
        case .largest: return "dsize"
        }
    }
}

struct SearchPage {
    let files: [EasynewsFile]
    let page: Int
    let pageSize: Int

    /// A full page suggests there is at least one more.
    var hasMore: Bool { files.count >= pageSize }
}

// MARK: - Errors

enum EasynewsError: LocalizedError {
    case notConfigured
    case badCredentials
    case http(Int)
    case emptyResponse
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your Easynews username and password in Settings."
        case .badCredentials:
            return "Easynews rejected those credentials. Check your username and password."
        case .http(let code):
            return "Easynews returned HTTP \(code)."
        case .emptyResponse:
            return "Easynews returned an empty response."
        case .decoding(let detail):
            return "Couldn't read the response: \(detail)"
        }
    }
}

// MARK: - Client

actor EasynewsClient {
    static let host = "https://members.easynews.com"

    private let session: URLSession

    /// Populated by the most recent search. Needed to build download URLs.
    private var downURL: String?
    private var dlFarm: String?
    private var dlPort: String?
    private var sid: String?

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    private static let videoExtensions = "mkv,mp4,avi,m4v,mov,webm,ts,m2ts,mpg,mpeg,wmv,flv"

    static let pageSize = 250

    private func request(
        query: String,
        page: Int,
        sort: SortOption,
        credentials: Credentials
    ) throws -> URLRequest {
        guard !credentials.username.isEmpty, !credentials.password.isEmpty else {
            throw EasynewsError.notConfigured
        }

        var comps = URLComponents(string: "\(Self.host)/2.0/search/solr-search/advanced")!
        comps.queryItems = [
            .init(name: "st", value: "adv"),
            .init(name: "sb", value: "1"),
            .init(name: "fex", value: Self.videoExtensions),
            .init(name: "fty[]", value: "VIDEO"),
            .init(name: "spamf", value: "1"),
            .init(name: "u", value: "1"),
            .init(name: "gx", value: "1"),
            .init(name: "pno", value: String(page)),
            .init(name: "sS", value: "3"),
            .init(name: "s1", value: sort.field),
            .init(name: "s1d", value: "-"),
            .init(name: "s2", value: "dsize"),
            .init(name: "s2d", value: "-"),
            .init(name: "s3", value: "dtime"),
            .init(name: "s3d", value: "-"),
            .init(name: "pby", value: String(Self.pageSize)),
            .init(name: "safeO", value: "0"),
            .init(name: "gps", value: query),
            .init(name: "sbj", value: query),
        ]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let raw = "\(credentials.username):\(credentials.password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        req.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")

        return req
    }

    func search(
        query: String,
        page: Int = 1,
        sort: SortOption = .relevance,
        credentials: Credentials
    ) async throws -> SearchPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchPage(files: [], page: page, pageSize: Self.pageSize) }

        let req = try request(query: trimmed, page: page, sort: sort, credentials: credentials)
        let (data, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 401, 403: throw EasynewsError.badCredentials
            default: throw EasynewsError.http(http.statusCode)
            }
        }

        guard !data.isEmpty else { throw EasynewsError.emptyResponse }

        let root: [String: JSONValue]
        do {
            root = try JSONDecoder().decode([String: JSONValue].self, from: data)
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "binary"
            throw EasynewsError.decoding(preview)
        }

        // Cache the download routing info for URL construction.
        downURL = root["downURL"]?.stringValue ?? root["down_url"]?.stringValue
        dlFarm = root["dlFarm"]?.stringValue
        dlPort = root["dlPort"]?.stringValue
        sid = root["sid"]?.stringValue

        guard let rows = root["data"]?.arrayValue else {
            // Some error responses put a message at the top level.
            if let msg = root["error"]?.stringValue ?? root["message"]?.stringValue {
                throw EasynewsError.decoding(msg)
            }
            return SearchPage(files: [], page: page, pageSize: Self.pageSize)
        }

        let files = rows.compactMap { $0.objectValue }.compactMap(EasynewsFile.from)
        return SearchPage(files: files, page: page, pageSize: Self.pageSize)
    }

    /// Builds the direct stream URL. Easynews serves these over HTTPS with range
    /// support, so VLC can seek without downloading the whole file.
    var hasRoutingInfo: Bool { !(downURL ?? "").isEmpty }

    func streamURL(for file: EasynewsFile, credentials: Credentials) -> URL? {
        guard var base = downURL, !base.isEmpty else { return nil }

        if base.hasPrefix("/") { base = Self.host + base }
        if base.hasSuffix("/") { base.removeLast() }

        let allowed = CharacterSet.urlPathAllowed
        let encodedName = file.baseName.addingPercentEncoding(withAllowedCharacters: allowed)
            ?? file.baseName

        var path = base
        if let farm = dlFarm, !farm.isEmpty { path += "/\(farm)" }
        if let port = dlPort, !port.isEmpty { path += "/\(port)" }
        path += "/\(file.id)\(file.ext)/\(encodedName)\(file.ext)"

        guard var comps = URLComponents(string: path) else { return nil }

        if let sid, !sid.isEmpty {
            comps.queryItems = [.init(name: "sid", value: sid)]
        }

        // Embed credentials so VLC authenticates even if it ignores the
        // :http-user / :http-pwd options we also pass on the media.
        comps.user = credentials.username
        comps.password = credentials.password

        return comps.url
    }
}
