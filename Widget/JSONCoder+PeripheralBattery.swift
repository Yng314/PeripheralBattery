import Foundation

extension JSONDecoder {
    static let peripheralBattery: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
