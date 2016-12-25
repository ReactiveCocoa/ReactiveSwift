import ReactiveSwift
import Result
import UIKit
import PlaygroundSupport

final class User {
	let username = MutableProperty("example")
}

final class ViewModel {
	struct FormError: Error {
		let reason: String

		static let invalidEmail = FormError(reason: "The address must end with `@reactivecocoa.io`.")
		static let mismatchEmail = FormError(reason: "The e-mail addresses do not match.")
	}

	let email: ActionProperty<String, FormError>
	let emailConfirmation: ActionProperty<String, FormError>
	let termsAccepted: MutableProperty<Bool>
	let reasons: Property<String>

	let submit: Action<(), String, NoError>

	init(_ user: User) {
		termsAccepted = MutableProperty(false)

		// Validation for `email`.
		email = user.username
			.map(forward: { !$0.isEmpty ? "\($0)@reactivecocoa.io" : "" },
			     attemptBackward: { Result($0.stripSuffix("@reactivecocoa.io"),
			                               failWith: .invalidEmail) })

		// Validation for `emailConfirmation`.
		emailConfirmation = MutableProperty("")
			.validate(with: email) { input, currentEmail in
				return input == currentEmail ? .success(()) : .failure(.mismatchEmail)
			}

		// The aggregate of latest validation results of all text fields.
		let validationResults = Property.combineLatest(email.validations,
		                                    emailConfirmation.validations)

		// The validation state of the entire form.
		let isValid = validationResults
			.combineLatest(with: termsAccepted)
			.map { $0.0?.value != nil && $0.1?.value != nil && $1 }

		let state = isValid.combineLatest(with: user.username)

		// Aggregate latest failures into stream of strings.
		reasons = validationResults.map {
			return [$0, $1]
				.flatMap { $0?.error?.reason }
				.joined(separator: "\n")
		}

		// The action to be invoked when the submit button is pressed.
		// It enables only if all the controls have passed their validations.
		submit = Action(state: state, enabledIf: { $0.0 }) { state, _ in
			return SignalProducer { observer, disposable in
				observer.send(value: state.1)
				observer.sendCompleted()
			}
		}
	}
}

final class ViewController {
	let view = FormView()
	private let viewModel: ViewModel

	init(_ viewModel: ViewModel) {
		self.viewModel = viewModel
	}

	func viewDidLoad() {
		// Initialize the interactive controls.
		view.emailField.text = viewModel.email.value
		view.emailConfirmationField.text = viewModel.emailConfirmation.value
		view.termsSwitch.isOn = false

		// Setup bindings with the interactive controls.
		viewModel.email <~ view.emailValues.skipNil()
		viewModel.emailConfirmation <~ view.emailConfirmationValues.skipNil()
		viewModel.termsAccepted <~ view.termsAccepted

		// Setup bindings with the invalidation reason label.
		view.invalidationReasons <~ viewModel.reasons

		// Setup the Action binding with the submit button.
		view.submit = viewModel.submit

		// Setup console messages.
		viewModel.submit.values.observeValues {
			print("ViewModel.submit: Username `\($0)`.")
		}

		viewModel.submit.completed.observeValues {
			print("ViewModel.submit: execution producer has completed.")
		}

		viewModel.email.validations.signal.observeValues {
			print("ViewModel.email: Validation result - \($0 != nil ? "\($0!)" : "No validation has ever been performed.")")
		}

		viewModel.emailConfirmation.validations.signal.observeValues {
			print("ViewModel.emailConfirmation: Validation result - \($0 != nil ? "\($0!)" : "No validation has ever been performed.")")
		}
	}
}

PlaygroundPage.current.needsIndefiniteExecution = true

let viewController = ViewController(ViewModel(User()))
PlaygroundPage.current.liveView = viewController.view
viewController.viewDidLoad()

extension String {
	func stripSuffix(_ suffix: String) -> String? {
		if let range = range(of: suffix) {
			return substring(with: startIndex ..< range.lowerBound)
		}
		return nil
	}
}
