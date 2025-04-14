public struct ReflectionInfo: Decodable {
    public let index: Int
    public let kind: String
    public let type: String
    public let arity: Int?
    public let fields: [String]
    public let methods: [[String]]
}
