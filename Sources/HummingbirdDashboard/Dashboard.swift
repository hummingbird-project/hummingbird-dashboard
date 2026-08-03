import OpenAPIRuntime

struct Dashboard: Sendable {
}

extension ServerTransport {
    func addDashboard(_ dashboard: Dashboard) throws {
        let api = APIImplementation(dashboard: dashboard)
        try api.registerHandlers(on: self)
    }
}
