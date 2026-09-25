import CryptoKit
import Foundation
import Security

/// Chrome's CRX3 package: a signed header in front of a ZIP (docs/EXTENSIONS.md §3.7).
///
/// Layout, from Chromium's `components/crx_file/crx3.proto`:
///
///     "Cr24" · u32le version (3) · u32le header size · CrxFileHeader · ZIP
///
/// `CrxFileHeader` carries RSA and ECDSA proofs (public key + signature) and
/// `signed_header_data`, whose field 1 is the 16-byte CRX id. Every signature
/// covers `"CRX3 SignedData\0" · u32le len(signed_header_data) · signed_header_data · ZIP`,
/// and the id is the first 16 bytes of SHA-256 over one of the keys. A Web
/// Store download carries the developer's key and Google's; both must verify.
public enum CRX3 {

    public enum Failure: Error, Equatable {
        case notACRX
        case unsupportedVersion(UInt32)
        case malformedHeader
        case noSignature
        case badSignature
        case idDoesNotMatchAnyKey
    }

    /// The verified package: its extension id and the ZIP it wraps.
    public struct Package: Sendable {
        public let id: String
        public let zip: Data
    }

    public static func unpack(_ data: Data) throws -> Package {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, bytes[0..<4] == [0x43, 0x72, 0x32, 0x34] else { throw Failure.notACRX }
        let version = littleEndian(bytes, at: 4)
        guard version == 3 else { throw Failure.unsupportedVersion(version) }
        let headerSize = Int(littleEndian(bytes, at: 8))
        guard headerSize <= bytes.count - 12 else { throw Failure.malformedHeader }
        let header = Array(bytes[12..<(12 + headerSize)])
        let zip = Array(bytes[(12 + headerSize)...])

        let (proofs, signedData) = try parse(header)
        guard let signedData,
              let crxID = try Protobuf.fields(signedData).first(where: { $0.number == 1 })?.bytes,
              crxID.count == 16
        else { throw Failure.malformedHeader }
        guard !proofs.isEmpty else { throw Failure.noSignature }

        var message = Array("CRX3 SignedData\0".utf8)
        message += withUnsafeBytes(of: UInt32(signedData.count).littleEndian, Array.init)
        message += signedData
        message += zip
        let signed = Data(message)
        for proof in proofs where !verify(signed, signature: proof.signature, spki: proof.key, isRSA: proof.isRSA) {
            throw Failure.badSignature
        }
        guard proofs.contains(where: { Array(SHA256.hash(data: $0.key).prefix(16)) == crxID }) else {
            throw Failure.idDoesNotMatchAnyKey
        }
        return Package(id: extensionID(crxID), zip: Data(zip))
    }

    private typealias Proof = (key: [UInt8], signature: [UInt8], isRSA: Bool)

    /// Field 2 is the RSA proofs, 3 the ECDSA ones, 10000 `signed_header_data`.
    private static func parse(_ header: [UInt8]) throws -> ([Proof], [UInt8]?) {
        var proofs: [Proof] = []
        var signedData: [UInt8]?
        for field in try Protobuf.fields(header) {
            switch field.number {
            case 2, 3:
                let proof = try Protobuf.fields(field.bytes)
                guard let key = proof.first(where: { $0.number == 1 })?.bytes,
                      let signature = proof.first(where: { $0.number == 2 })?.bytes
                else { throw Failure.malformedHeader }
                proofs.append((key, signature, field.number == 2))
            case 10_000:
                signedData = field.bytes
            default:
                continue
            }
        }
        return (proofs, signedData)
    }

    /// Chrome's id for a public key: SHA-256 of the DER `SubjectPublicKeyInfo`,
    /// first 16 bytes, each nibble written as `a`…`p`. The same rule turns a
    /// manifest's `key` into the id Chrome would give the unpacked extension.
    public static func extensionID(publicKey spki: Data) -> String {
        extensionID(Array(SHA256.hash(data: spki).prefix(16)))
    }

    private static func extensionID(_ bytes: [UInt8]) -> String {
        let letters = Array("abcdefghijklmnop")
        return String(bytes.flatMap { [letters[Int($0 >> 4)], letters[Int($0 & 0x0F)]] })
    }

    private static func littleEndian(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }

    // MARK: - Signatures

    private static func verify(_ message: Data, signature: [UInt8], spki: [UInt8], isRSA: Bool) -> Bool {
        guard let raw = DER.subjectPublicKey(spki) else { return false }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: isRSA ? kSecAttrKeyTypeRSA : kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        guard let key = SecKeyCreateWithData(Data(raw) as CFData, attributes as CFDictionary, nil) else { return false }
        let algorithm: SecKeyAlgorithm = isRSA ? .rsaSignatureMessagePKCS1v15SHA256 : .ecdsaSignatureMessageX962SHA256
        return SecKeyVerifySignature(key, algorithm, message as CFData, Data(signature) as CFData, nil)
    }
}

/// Just enough protobuf to read CRX3's header: length-delimited fields are
/// returned, varints are skipped, and anything else is malformed.
enum Protobuf {

    struct Field {
        let number: Int
        let bytes: [UInt8]
    }

    static func fields(_ bytes: [UInt8]) throws -> [Field] {
        var result: [Field] = []
        var index = 0
        while index < bytes.count {
            let tag = try varint(bytes, &index)
            let number = Int(tag >> 3)
            switch tag & 7 {
            case 0:
                _ = try varint(bytes, &index)
            case 2:
                let length = Int(try varint(bytes, &index))
                guard length <= bytes.count - index else { throw CRX3.Failure.malformedHeader }
                result.append(Field(number: number, bytes: Array(bytes[index..<(index + length)])))
                index += length
            default:
                throw CRX3.Failure.malformedHeader
            }
        }
        return result
    }

    private static func varint(_ bytes: [UInt8], _ index: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 7) {
            guard index < bytes.count else { throw CRX3.Failure.malformedHeader }
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << UInt64(shift)
            if byte & 0x80 == 0 { return value }
        }
        throw CRX3.Failure.malformedHeader
    }
}

/// The one DER walk CRX3 needs. `SecKeyCreateWithData` takes PKCS#1 for RSA
/// and an X9.63 point for EC, which is exactly the BIT STRING inside a
/// `SubjectPublicKeyInfo`: SEQUENCE { SEQUENCE algorithm, BIT STRING key }.
enum DER {

    static func subjectPublicKey(_ spki: [UInt8]) -> [UInt8]? {
        var index = 0
        guard let outer = element(spki, &index), outer.tag == 0x30 else { return nil }
        var inner = 0
        guard let algorithm = element(outer.body, &inner), algorithm.tag == 0x30,
              let key = element(outer.body, &inner), key.tag == 0x03,
              key.body.first == 0
        else { return nil }
        return Array(key.body.dropFirst())
    }

    private static func element(_ bytes: [UInt8], _ index: inout Int) -> (tag: UInt8, body: [UInt8])? {
        guard index + 2 <= bytes.count else { return nil }
        let tag = bytes[index]
        var length = Int(bytes[index + 1])
        index += 2
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count <= 4, index + count <= bytes.count else { return nil }
            length = bytes[index..<(index + count)].reduce(0) { $0 << 8 | Int($1) }
            index += count
        }
        guard length <= bytes.count - index else { return nil }
        defer { index += length }
        return (tag, Array(bytes[index..<(index + length)]))
    }
}
