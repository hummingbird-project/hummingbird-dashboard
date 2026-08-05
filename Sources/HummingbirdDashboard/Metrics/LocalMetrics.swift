//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import DequeModule
public import Metrics
import Synchronization

#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

public final class LocalMetrics: MetricsFactory, Sendable {
    public struct Key: Hashable, Sendable {
        let label: String
        let dimensions: [(String, String)]

        public init(_ label: String, dimensions: [(String, String)] = []) {
            self.label = label
            self.dimensions = dimensions
        }

        public static func == (lhs: Key, rhs: Key) -> Bool {
            lhs.label == rhs.label && Dictionary(uniqueKeysWithValues: lhs.dimensions) == Dictionary(uniqueKeysWithValues: rhs.dimensions)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.label)
            hasher.combine(Dictionary(uniqueKeysWithValues: dimensions))
        }
    }

    public final class EventStream<Value: Sendable>: Sendable {
        public struct Event: Sendable {
            public let time: Date
            public let value: Value
            public let dimensions: [(String, String)]
        }
        let _events: Mutex<Deque<Event>>
        let maxAge: TimeInterval

        init(maxAge: TimeInterval, value: Value.Type = Value.self) {
            self._events = .init(.init())
            self.maxAge = maxAge
        }

        func pushEvent(_ value: Value, dimensions: [(String, String)]) {
            self._events.withLock { events in
                events.append(Event(time: .now, value: value, dimensions: dimensions))
                let cullDate = Date.now - maxAge
                while events.count > 1, events[events.startIndex].time < cullDate {
                    _ = events.popFirst()
                }
                return
            }
        }
    }

    protocol MetricProtocol {
        associatedtype Value: Sendable
        var label: String { get }
        var dimensions: [(String, String)] { get }
        init(label: String, dimensions: [(String, String)], maxAge: TimeInterval, events: EventStream<Value>)
    }

    struct Metrics<M: MetricProtocol> {
        var metrics: [Key: M]
        var events: [String: EventStream<M.Value>]

        init() {
            self.metrics = [:]
            self.events = [:]
        }
    }
    let _counters: Mutex<Metrics<Counter>>
    let _meters: Mutex<Metrics<Meter>>
    let _recorders: Mutex<Metrics<Recorder>>
    let _timers: Mutex<Metrics<Timer>>

    let maxAgeInSeconds: TimeInterval

    public init(maxAge: Duration) {
        self._counters = .init(.init())
        self._meters = .init(.init())
        self._recorders = .init(.init())
        self._timers = .init(.init())
        self.maxAgeInSeconds = maxAge / Duration.seconds(1)
    }

    public func makeCounter(label: String, dimensions: [(String, String)]) -> any CounterHandler {
        self._counters.withLock { counters in
            let events = counters.events[label, updating: .init(maxAge: self.maxAgeInSeconds)]
            let key: Key = .init(label, dimensions: dimensions)
            return counters.metrics[key, updating: Counter(label: label, dimensions: dimensions, maxAge: self.maxAgeInSeconds, events: events)]
        }
    }

    public func makeMeter(label: String, dimensions: [(String, String)]) -> any MeterHandler {
        self._meters.withLock { meters in
            let events = meters.events[label, updating: .init(maxAge: self.maxAgeInSeconds)]
            let key: Key = .init(label, dimensions: dimensions)
            return meters.metrics[key, updating: Meter(label: label, dimensions: dimensions, maxAge: self.maxAgeInSeconds, events: events)]
        }
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> any RecorderHandler {
        self._recorders.withLock { recorders in
            let events = recorders.events[label, updating: .init(maxAge: self.maxAgeInSeconds)]
            let key: Key = .init(label, dimensions: dimensions)
            return recorders.metrics[key, updating: Recorder(label: label, dimensions: dimensions, maxAge: self.maxAgeInSeconds, events: events)]
        }
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> any TimerHandler {
        self._timers.withLock { timers in
            let events = timers.events[label, updating: .init(maxAge: self.maxAgeInSeconds)]
            let key: Key = .init(label, dimensions: dimensions)
            return timers.metrics[key, updating: Timer(label: label, dimensions: dimensions, maxAge: self.maxAgeInSeconds, events: events)]
        }
    }

    public func destroyCounter(_ handler: any CounterHandler) {
        if let counter = handler as? Counter {
            _ = self._counters.withLock { $0.metrics.removeValue(forKey: counter.key) }
        }
    }

    public func destroyMeter(_ handler: any MeterHandler) {
        if let meter = handler as? Meter {
            _ = self._counters.withLock { $0.metrics.removeValue(forKey: meter.key) }
        }
    }

    public func destroyRecorder(_ handler: any RecorderHandler) {
        if let recoder = handler as? Recorder {
            _ = self._counters.withLock { $0.metrics.removeValue(forKey: recoder.key) }
        }
    }

    public func destroyTimer(_ handler: any TimerHandler) {
        if let timer = handler as? Timer {
            _ = self._counters.withLock { $0.metrics.removeValue(forKey: timer.key) }
        }
    }

    public final class Counter: CounterHandler, MetricProtocol {
        public typealias Value = Int64
        public let label: String
        public let dimensions: [(String, String)]
        public let events: EventStream<Value>
        let value: Atomic<Value>

        init(label: String, dimensions: [(String, String)] = [], maxAge: TimeInterval, events: EventStream<Value>) {
            self.label = label
            self.dimensions = dimensions
            self.events = events
            self.value = .init(0)
        }

        public func increment(by amount: Int64) {
            let (_, newValue) = self.value.add(amount, ordering: .relaxed)
            events.pushEvent(newValue, dimensions: dimensions)
        }

        public func reset() {
            self.value.store(0, ordering: .relaxed)
            events.pushEvent(0, dimensions: dimensions)
        }
    }

    public final class Meter: MeterHandler, MetricProtocol {
        public typealias Value = Double
        public let label: String
        public let dimensions: [(String, String)]
        public let events: EventStream<Value>
        let value: Atomic<Value>

        init(label: String, dimensions: [(String, String)] = [], maxAge: TimeInterval, events: EventStream<Value>) {
            self.label = label
            self.dimensions = dimensions
            self.events = events
            self.value = .init(0)
        }

        public func set(_ value: Int64) {
            self.set(Double(value))
        }

        public func set(_ value: Double) {
            self.value.store(value, ordering: .relaxed)
            events.pushEvent(value, dimensions: dimensions)
        }

        public func increment(by amount: Double) {
            var result = (
                exchanged: false,
                original: self.value.load(ordering: .relaxed)
            )
            var newValue: Value
            repeat {
                newValue = result.original + amount

                result = self.value.weakCompareExchange(
                    expected: result.original,
                    desired: newValue,
                    ordering: .relaxed
                )
            } while !result.exchanged

            events.pushEvent(newValue, dimensions: dimensions)
        }

        public func decrement(by amount: Double) {
            self.increment(by: -amount)
        }
    }

    public final class Recorder: RecorderHandler, MetricProtocol {
        public typealias Value = Double
        public let label: String
        public let dimensions: [(String, String)]
        public let events: EventStream<Value>

        init(label: String, dimensions: [(String, String)] = [], maxAge: TimeInterval, events: EventStream<Value>) {
            self.label = label
            self.dimensions = dimensions
            self.events = events
        }

        public func record(_ value: Int64) {
            events.pushEvent(Double(value), dimensions: dimensions)
        }

        public func record(_ value: Double) {
            events.pushEvent(value, dimensions: dimensions)
        }
    }

    public final class Timer: TimerHandler, MetricProtocol {
        public typealias Value = Int64
        public let label: String
        public let dimensions: [(String, String)]
        public let events: EventStream<Value>

        init(label: String, dimensions: [(String, String)] = [], maxAge: TimeInterval, events: EventStream<Value>) {
            self.label = label
            self.dimensions = dimensions
            self.events = events
        }

        public func recordNanoseconds(_ duration: Int64) {
            events.pushEvent(duration, dimensions: self.dimensions)
        }
    }
}

extension LocalMetrics {
    public var counters: some Collection<Counter> {
        self._counters.withLock { $0.metrics.values }
    }

    public var meters: some Collection<Meter> {
        self._meters.withLock { $0.metrics.values }
    }

    public var recorders: some Collection<Recorder> {
        self._recorders.withLock { $0.metrics.values }
    }

    public var timers: some Collection<Timer> {
        self._timers.withLock { $0.metrics.values }
    }

    public func counterEvents(label: String) -> EventStream<Counter.Value>? {
        self._counters.withLock { $0.events[label] }
    }

    public func meterEvents(label: String) -> EventStream<Meter.Value>? {
        self._meters.withLock { $0.events[label] }
    }

    public func recorderEvents(label: String) -> EventStream<Recorder.Value>? {
        self._recorders.withLock { $0.events[label] }
    }

    public func timerEvents(label: String) -> EventStream<Timer.Value>? {
        self._timers.withLock { $0.events[label] }
    }
}

extension LocalMetrics.EventStream {
    public var count: Int {
        self._events.withLock { $0.count }
    }

    public var events: some RandomAccessCollection<Event> {
        self._events.withLock { $0 }
    }

    @_disfavoredOverload
    public func filter(dimensions: some Collection<(String, String)>) -> [Event] {
        let events = self._events.withLock { $0 }
        var output: [Event] = []
        output.reserveCapacity(events.count)

        outerLoop: for event in events {
            for dimension in dimensions {
                if event.dimensions.first(where: { $0.0 == dimension.0 })?.1 != dimension.1 {
                    continue outerLoop
                }
            }
            output.append(event)
        }
        return output
    }

    @available(macOS 26, iOS 26, tvOS 26, *)
    public func filter<let count: Int>(dimensions: InlineArray<count, (String, String)>) -> [Event] {
        let events = self._events.withLock { $0 }
        var output: [Event] = []
        output.reserveCapacity(events.count)

        outerLoop: for event in events {
            for index in dimensions.indices {
                if event.dimensions.first(where: { $0.0 == dimensions[index].0 })?.1 != dimensions[index].1 {
                    continue outerLoop
                }
            }
            output.append(event)
        }
        return output
    }
}

extension LocalMetrics.MetricProtocol {
    var key: LocalMetrics.Key {
        .init(self.label, dimensions: self.dimensions)
    }
}

extension Dictionary {
    subscript(
        key: Key,
        updating defaultValue: @autoclosure () -> Value
    ) -> Value {
        mutating get {
            if let value = self[key] {
                return value
            }
            let value = defaultValue()
            self[key] = value
            return value
        }
    }
}
