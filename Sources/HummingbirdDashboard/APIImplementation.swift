//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import OpenAPIRuntime

struct APIImplementation: APIProtocol {
    let dashboard: Dashboard

    func getHello(_ input: Operations.GetHello.Input) async throws -> Operations.GetHello.Output {
        .ok(.init(body: .plainText("Hello!")))
    }
}
