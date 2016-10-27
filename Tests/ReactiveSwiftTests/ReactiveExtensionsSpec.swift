import Nimble
import Quick
import ReactiveSwift
import Result

private final class TestExtensionProvider: ReactiveExtensionsProvider {
	let instanceProperty = "instance"
	static let staticProperty = "static"
}

extension Reactive where Base: TestExtensionProvider {
	var instanceProperty: SignalProducer<String, NoError> {
		return SignalProducer(value: base.instanceProperty)
	}

	static var staticProperty: SignalProducer<String, NoError> {
		return SignalProducer(value: Base.staticProperty)
	}
}

final class ReactiveExtensionsSpec: QuickSpec {
	override func spec() {
		describe("ReactiveExtensions") {
			it("allows reactive extensions of instances") {
				expect(TestExtensionProvider().reactive.instanceProperty.first()?.value) == "instance"
			}

			it("allows reactive extensions of types") {
				expect(TestExtensionProvider.reactive.staticProperty.first()?.value) == "static"
			}
		}
	}
}
