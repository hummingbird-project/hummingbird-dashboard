//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import OpenAPIRuntime

struct Dashboard: Sendable {
}

extension ServerTransport {
    func addDashboard(_ dashboard: Dashboard) throws {
        let api = APIImplementation(dashboard: dashboard)
        try api.registerHandlers(on: self)
    }
}
