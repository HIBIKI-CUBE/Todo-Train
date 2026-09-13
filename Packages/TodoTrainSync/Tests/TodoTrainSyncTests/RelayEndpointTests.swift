import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Relay endpoint")
struct RelayEndpointTests {
    @Test func productionIsCustomDomain() throws {
        let url = try #require(URL(string: RelayEndpoint.productionURLString))
        #expect(url.scheme == "https")
        #expect(url.host == "todo-train.hibiki-cube.dev")
        #expect(url.path.isEmpty || url.path == "/")
    }

    @Test func developIsNestedCustomDomain() throws {
        let url = try #require(URL(string: RelayEndpoint.developURLString))
        #expect(url.scheme == "https")
        #expect(url.host == "dev.todo-train.hibiki-cube.dev")
        #expect(url.path.isEmpty || url.path == "/")
    }

    @Test func defaultIsHostedRelay() throws {
        let url = try #require(URL(string: RelayEndpoint.defaultURLString))
        #expect(url.scheme == "https")
        #expect(
            url.host == "dev.todo-train.hibiki-cube.dev"
                || url.host == "todo-train.hibiki-cube.dev"
        )
    }

    @Test func coalesceStoredPromotesOldLocalDefault() {
        #expect(RelayEndpoint.coalesceStored(nil) == RelayEndpoint.defaultURLString)
        #expect(RelayEndpoint.coalesceStored("") == RelayEndpoint.defaultURLString)
        #expect(RelayEndpoint.coalesceStored("http://127.0.0.1:8787") == RelayEndpoint.defaultURLString)
        #expect(
            RelayEndpoint.coalesceStored("https://todo-train.hibiki-cube.dev")
                == "https://todo-train.hibiki-cube.dev"
        )
    }
}
