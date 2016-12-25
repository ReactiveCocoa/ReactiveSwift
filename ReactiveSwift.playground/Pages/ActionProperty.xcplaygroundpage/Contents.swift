import ReactiveSwift
import Result
import UIKit
import PlaygroundSupport

final class User {
	let email = MutableProperty("")
}

final class ViewModel {
	let email: ActionProperty<String, FormError>
	let emailConfirmation: ActionProperty<String, FormError>
	let termsAccepted = MutableProperty<Bool>(false)
	let submit: Action<(), (), NoError>
	let reasons: Property<String>

	init(_ user: User) {
		email = user.email
			.validate { input in
				print("ViewModel.email predicate received input: \(input)")

				if input.characters.contains("@") {
					return .success(())
				} else {
					return .failure(FormError("Invalid email address."))
				}
			}

		emailConfirmation = MutableProperty("")
			.validate { [email] input in
				print("ViewModel.emailConfirmation predicate received input: \(input)")

				return input == email.value ? .success(()) : .failure(FormError("The e-mail addresses do not match."))
			}

		let validationSignal = Signal.combineLatest(
			email.validations.map { $0.value != nil },
			emailConfirmation.validations.map { $0.value != nil },
			termsAccepted.signal)
			.on(value: { print("Validation Status: \($0)") })
			.map { $0 && $1 && $2 }

		let allFieldsValid = Property(initial: false,
		                              then: validationSignal)

		reasons = Property(initial: nil, then: email.validations.map { $0.error })
			.combineLatest(with: Property(initial: nil, then: emailConfirmation.validations.map { $0.error }))
			.map { [$0, $1].flatMap { $0?.reason }.joined(separator: "\n") }

		print("Validation Status: false")


		submit = Action(state: allFieldsValid, enabledIf: { $0 }) { _ in
			return SignalProducer { observer, disposable in
				print("ViewModel.submit execution producer has started.")
				observer.sendCompleted()
			}
		}
	}
}

let viewModel = ViewModel(User())
let formView = setup()

formView.emailField.text = viewModel.email.value
formView.emailConfirmationField.text = viewModel.emailConfirmation.value
formView.termsSwitch.isOn = false

viewModel.email <~ formView.emailValues.skipNil()
viewModel.emailConfirmation <~ formView.emailConfirmationValues.skipNil()
viewModel.termsAccepted <~ formView.termsAccepted

formView.invalidationReasons <~ viewModel.reasons

formView.submit = viewModel.submit

func setup() -> FormView {
	let view = FormView()

	PlaygroundPage.current.needsIndefiniteExecution = true
	PlaygroundPage.current.liveView = view

	return view
}

struct FormError: Error {
	let reason: String
	init(_ reason: String) {
		self.reason = reason
	}
}
