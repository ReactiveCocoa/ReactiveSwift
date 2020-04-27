#if canImport(Combine)
import Combine

extension SignalProducerConvertible {
	@available(macOS 10.15, iOS 13.0, tvOS 13.0, macCatalyst 13.0, watchOS 6.0, *)
	public func eraseToAnyPublisher() -> AnyPublisher<Value, Error> {
		publisher().eraseToAnyPublisher()
	}

	@available(macOS 10.15, iOS 13.0, tvOS 13.0, macCatalyst 13.0, watchOS 6.0, *)
	public func publisher() -> ProducerPublisher<Value, Error> {
		ProducerPublisher(base: producer)
	}
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, macCatalyst 13.0, watchOS 6.0, *)
public struct ProducerPublisher<Output, Failure: Swift.Error>: Publisher {
	public let base: SignalProducer<Output, Failure>

	public init(base: SignalProducer<Output, Failure>) {
		self.base = base
	}

	public func receive<S>(subscriber: S) where S : Subscriber, Output == S.Input, Failure == S.Failure {
		let subscription = Subscription(subscriber: subscriber, base: base)
		subscription.bootstrap()
	}

	final class Subscription<S: Subscriber>: Combine.Subscription where Output == S.Input, Failure == S.Failure {
		let subscriber: S
		let base: SignalProducer<Output, Failure>
		let state: Atomic<State>

		init(subscriber: S, base: SignalProducer<Output, Failure>) {
			self.subscriber = subscriber
			self.base = base
			self.state = Atomic(State())
		}

		func bootstrap() {
			subscriber.receive(subscription: self)
		}

		func request(_ incoming: Subscribers.Demand) {
			let response: DemandResponse = state.modify { state in
				guard state.hasCancelled == false else {
					return .noAction
				}

				guard state.hasStarted else {
					state.hasStarted = true
					state.requested = incoming
					return .startUpstream
				}

				state.requested = state.requested + incoming
				let unsatified = state.requested - state.satisfied

				if let max = unsatified.max {
					let dequeueCount = Swift.min(state.buffer.count, max)
					state.satisfied += dequeueCount

					defer { state.buffer.removeFirst(dequeueCount) }
					return .satisfyDemand(Array(state.buffer.prefix(dequeueCount)))
				} else {
					defer { state.buffer = [] }
					return .satisfyDemand(state.buffer)
				}
			}

			switch response {
			case let .satisfyDemand(output):
				var demand: Subscribers.Demand = .none

				for output in output {
					demand += subscriber.receive(output)
				}

				if demand != .none {
					request(demand)
				}

			case .startUpstream:
				let disposable = base.start { [weak self] event in
					guard let self = self else { return }

					switch event {
					case let .value(output):
						let (shouldSendImmediately, isDemandUnlimited): (Bool, Bool) = self.state.modify { state in
							guard state.hasCancelled == false else { return (false, false) }

							let unsatified = state.requested - state.satisfied

							if let count = unsatified.max, count >= 1 {
								assert(state.buffer.count == 0)
								state.satisfied += 1
								return (true, false)
							} else if unsatified == .unlimited {
								assert(state.buffer.isEmpty)
								return (true, true)
							} else {
								assert(state.requested == state.satisfied)
								state.buffer.append(output)
								return (false, false)
							}
						}

						if shouldSendImmediately {
							let demand = self.subscriber.receive(output)

							if isDemandUnlimited == false && demand != .none {
								self.request(demand)
							}
						}

					case .completed, .interrupted:
						self.cancel()
						self.subscriber.receive(completion: .finished)

					case let .failed(error):
						self.cancel()
						self.subscriber.receive(completion: .failure(error))
					}
				}

				let shouldDispose: Bool = state.modify { state in
					guard state.hasCancelled == false else { return true }
					state.producerSubscription = disposable
					return false
				}

				if shouldDispose {
					disposable.dispose()
				}

			case .noAction:
				break
			}
		}

		func cancel() {
			let disposable = state.modify { $0.cancel() }
			disposable?.dispose()
		}

		struct State {
			var requested: Subscribers.Demand = .none
			var satisfied: Subscribers.Demand = .none

			var buffer: [Output] = []

			var producerSubscription: Disposable?
			var hasStarted = false
			var hasCancelled = false

			init() {
				producerSubscription = nil
				hasStarted = false
				hasCancelled = false
			}

			mutating func cancel() -> Disposable? {
				hasCancelled = true
				defer { producerSubscription = nil }
				return producerSubscription
			}
		}

		enum DemandResponse {
			case startUpstream
			case satisfyDemand([Output])
			case noAction
		}
	}
}
#endif
