import OpenAPIRuntime

struct APIImplementation: APIProtocol {
    let dashboard: Dashboard

    func getHello(_ input: Operations.GetHello.Input) async throws -> Operations.GetHello.Output {
        .ok(.init(body: .plainText("Hello!")))
    }
}
