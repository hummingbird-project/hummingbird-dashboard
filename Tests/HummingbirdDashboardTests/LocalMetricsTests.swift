//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import DequeModule
import Foundation
import Hummingbird
import HummingbirdTesting
import Metrics
import Testing

@testable import HummingbirdDashboard

struct LocalMetricsTests {
    @Test func metricsExist() async throws {
        let router = Router()
        router.addMiddleware {
            MetricsMiddleware()
        }
        router.get { _, _ in
            "Hello"
        }
        let app = Application(router: router)
        let metrics = LocalMetrics(maxAge: .seconds(3600))
        try await withMetricsFactory(metrics) {
            try await app.test(.router) { client in
                _ = try await client.execute(uri: "/", method: .get)
            }
        }
        let counters = metrics.counters
        #expect(counters.contains { $0.label == "hb.requests" })
        #expect(counters.contains { $0.label == "hb.request.errors" })
        let meters = metrics.meters
        #expect(meters.contains { $0.label == "http.server.active_requests" })
        let timers = metrics.timers
        #expect(timers.contains { $0.label == "http.server.request.duration" })
    }

    @Test func metricsRecorded() async throws {
        let router = Router()
        router.addMiddleware {
            MetricsMiddleware()
        }
        router.get { _, _ in
            "Hello"
        }
        let app = Application(router: router)
        let metrics = LocalMetrics(maxAge: .seconds(3600))
        try await withMetricsFactory(metrics) {
            try await app.test(.router) { client in
                _ = try await client.execute(uri: "/", method: .get)
                _ = try await client.execute(uri: "/", method: .get)
            }
        }
        let counterEvents = try #require(metrics.counterEvents(label: "hb.requests")?.events)
        #expect(counterEvents.count == 2)
        #expect(counterEvents[counterEvents.startIndex].value == 1)
        #expect(counterEvents[counterEvents.index(after: counterEvents.startIndex)].value == 2)
        let timerEvents = try #require(metrics.timerEvents(label: "http.server.request.duration")?.events)
        #expect(timerEvents.count == 2)
    }

    @Test func filterMetricsRecorded() async throws {
        let router = Router()
        router.addMiddleware {
            MetricsMiddleware()
        }
        router.get { _, _ in
            "Hello"
        }
        router.put { _, _ in
            "Hello"
        }
        let app = Application(router: router)
        let metrics = LocalMetrics(maxAge: .seconds(3600))
        try await withMetricsFactory(metrics) {
            try await app.test(.router) { client in
                _ = try await client.execute(uri: "/", method: .get)
                _ = try await client.execute(uri: "/", method: .put)
                _ = try await client.execute(uri: "/test", method: .put)
                _ = try await client.execute(uri: "/test", method: .put)
                _ = try await client.execute(uri: "/", method: .get)
            }
        }
        let putEvents = try #require(
            metrics.counterEvents(label: "hb.requests")?.filter(dimensions: [("http.request.method", "PUT")])
        )
        #expect(putEvents.count == 3)
        #expect(putEvents[0].value == 1)
        #expect(putEvents[1].value == 1)
        #expect(putEvents[2].value == 2)
        let notFoundEvents = try #require(
            metrics.counterEvents(label: "hb.requests")?.filter(dimensions: [("http.response.status_code", "404")])
        )
        #expect(notFoundEvents.count == 2)
        #expect(notFoundEvents[0].value == 1)
        #expect(notFoundEvents[1].value == 2)
    }

    @Test func cullingOldMetrics() async throws {
        let router = Router()
        router.addMiddleware {
            MetricsMiddleware()
        }
        router.get { _, _ in
            "Hello"
        }
        let app = Application(router: router)
        let metrics = LocalMetrics(maxAge: .seconds(2))
        try await withMetricsFactory(metrics) {
            try await app.test(.router) { client in
                _ = try await client.execute(uri: "/", method: .get)
                try await Task.sleep(for: .seconds(2.5))
                _ = try await client.execute(uri: "/", method: .get)
            }
        }
        let counterEvents = try #require(metrics.counterEvents(label: "hb.requests")?.events)
        #expect(counterEvents.count == 1)
        #expect(counterEvents[counterEvents.startIndex].value == 2)
    }
}
