import Foundation
import GregularJellyfin
import Testing

struct InMemoryCredentialStoreTests {
    @Test func keepsTheRules() throws {
        try CredentialStoreRules.check(InMemoryCredentialStore())
    }
}
