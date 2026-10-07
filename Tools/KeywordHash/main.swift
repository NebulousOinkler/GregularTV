import Foundation
import GregularCore

// keyword-hash: the hash of a special mode's keyword, for special-modes.jsonc
// (see SpecialModeRegistry). A tool for whoever adds a mode; not part of the app.
//
//     swift run keyword-hash "THE KEYWORD"

let keyword = CommandLine.arguments.dropFirst().joined(separator: " ")
do {
    print(try SpecialModeRegistry.keywordHash(for: keyword))
} catch {
    print("keyword-hash: \(error)")
    exit(1)
}
