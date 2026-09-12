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
}
