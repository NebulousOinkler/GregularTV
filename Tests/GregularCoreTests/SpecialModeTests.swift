import Foundation
import Testing
@testable import GregularCore

/// Special modes' keywords, typed where a schedule code goes, and kept only
/// as hashes.
struct SpecialModeTests {
    /// A registry file, with `keywords` hashed as `keyword-hash` would.
    static func registry(_ modes: [(id: String, keywords: [String], library: String?)]) throws -> SpecialModeRegistry {
        let entries = try modes.map { mode in
            let hashes = try mode.keywords.map { #""\#(try SpecialModeRegistry.keywordHash(for: $0))""# }
            let library = mode.library.map { #", "library": "\#($0)""# } ?? ""
            return #"{ "id": "\#(mode.id)", "keywordHashes": [\#(hashes.joined(separator: ","))]\#(library) }"#
        }
        return try SpecialModeRegistry.load(from: Data(#"{ "modes": [\#(entries.joined(separator: ","))] }"#.utf8))
    }

    static func modes() throws -> SpecialModeRegistry {
        try registry([("everything", ["OPEN UP, SESAME", "Abracadabra"], nil), ("own-library", ["SING-ALONG"], "Songs")])
    }

    @Test func theBundledModesLoad() throws {
        _ = try SpecialModeRegistry.bundled()
    }

    /// Anyone reading the file is told what it is.
    @Test func theBundledFileSaysItHoldsHashesOfSecretKeywords() {
        let file = String(decoding: Data(PackageResources.special_modes_jsonc), as: UTF8.self)
        #expect(file.hasPrefix("// This file holds the SHA-256 hashes of secret keywords"))
    }

    @Test func theFileHoldsHashesNotKeywords() throws {
        #expect(try SpecialModeRegistry.keywordHash(for: "sing along") == SHA256.hex("gregular-special-mode:SINGALONG"))
        #expect(try SpecialModeRegistry.keywordHash(for: "sing along").count == 64)
    }

    @Test func eachModeSaysWhereItsProgrammesComeFrom() throws {
        #expect(try Self.modes().modes == [
            SpecialMode(id: "everything", catalogue: .wholeLibrary),
            SpecialMode(id: "own-library", catalogue: .library(named: "Songs")),
        ])
    }

    @Test(arguments: ["open up, sesame", "OPENUP,SESAME", "Open-Up, Sesame", " abracadabra "])
    func typingAKeywordIsForgiving(typed: String) throws {
        #expect(try Self.modes().mode(forKeyword: typed)?.id == "everything")
    }

    @Test func whatsTypedIsACodeAKeywordOrNeither() throws {
        let modes = try Self.modes()
        #expect(CodeEntry("7kqm2 x9pda", specialModes: modes) == .schedule(ScheduleCode("7KQM2-X9PDA")!))
        #expect(CodeEntry("sing along", specialModes: modes) == .specialMode(SpecialMode(id: "own-library", catalogue: .library(named: "Songs"))))
        #expect(CodeEntry("open up, sesame please", specialModes: modes) == nil)
        #expect(CodeEntry("abracadabra", specialModes: SpecialModeRegistry()) == nil, "No modes, no keywords")
    }

    /// A front end's modes: the others' keywords mean nothing there.
    @Test func aRegistryCanBeLimitedToSomeModes() throws {
        let limited = try Self.modes().limited(to: ["own-library"])
        #expect(limited.modes.map(\.id) == ["own-library"])
        #expect(limited.mode(forKeyword: "abracadabra") == nil)
    }

    /// A schedule code is always read as one, so it would never open a mode.
    @Test func aKeywordCantBeAScheduleCodeOrNothing() {
        #expect(throws: SpecialModeRegistry.KeywordProblem.isAScheduleCode) { try SpecialModeRegistry.keywordHash(for: "open sesame") }
        #expect(throws: SpecialModeRegistry.KeywordProblem.empty) { try SpecialModeRegistry.keywordHash(for: " - ") }
    }

    @Test func aKeywordMeansOneThing() throws {
        #expect(throws: SpecialModeRegistry.LoadError.duplicateKeyword(try SpecialModeRegistry.keywordHash(for: "ONE"))) {
            try Self.registry([("a", ["ONE"], nil), ("b", ["o-n-e"], nil)])
        }
        #expect(throws: SpecialModeRegistry.LoadError.duplicateMode("a")) { try Self.registry([("a", ["ONE"], nil), ("a", ["TWO"], nil)]) }
        #expect(throws: SpecialModeRegistry.LoadError.noKeywords("a")) { try Self.registry([("a", [], nil)]) }
        #expect(throws: SpecialModeRegistry.LoadError.notAHash("sesame")) {
            try SpecialModeRegistry.load(from: Data(#"{ "modes": [ { "id": "a", "keywordHashes": ["SESAME"] } ] }"#.utf8))
        }
    }

    @Test func commentLinesAreIgnored() throws {
        let file = "// What this is.\n{ \"modes\": [\n  // None yet.\n] }\n"
        #expect(try SpecialModeRegistry.load(from: Data(file.utf8)).modes.isEmpty)
    }

    /// FIPS 180-4's examples.
    @Test(arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        (String(repeating: "a", count: 1000), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3"),
    ])
    func sha256(text: String, digest: String) {
        #expect(SHA256.hex(text) == digest)
    }
}
