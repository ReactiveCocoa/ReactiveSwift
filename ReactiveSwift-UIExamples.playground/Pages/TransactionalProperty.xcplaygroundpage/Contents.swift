import ReactiveSwift
import Result
import UIKit
import PlaygroundSupport

final class ViewModel {
	struct FormError: Error {
		let reason: String

		static let invalidEmail = FormError(reason: "The address must end with `@reactivecocoa.io`.")
		static let mismatchEmail = FormError(reason: "The e-mail addresses do not match.")
		static let usernameUnavailable = FormError(reason: "The username has been taken.")
	}

	let email: PropertyEditor<String, FormError>
	let emailConfirmation: PropertyEditor<String, FormError>
	let termsAccepted: MutableProperty<Bool>
	let reasons: Signal<String, NoError>

	let submit: Action<(), (), FormError>

	init(userService: UserService) {
		termsAccepted = MutableProperty(false)

		let username = MutableProperty("example")

		// Setup property validation for `email`.
		email = username.map(forward: { !$0.isEmpty ? "\($0)@reactivecocoa.io" : "" },
		                     attemptBackward: { Result($0.stripSuffix("@reactivecocoa.io"),
		                                               failWith: .invalidEmail) })

		// Setup property validation for `emailConfirmation`.
		emailConfirmation = MutableProperty("")
			.validate(with: email) { input, currentEmail in
				return input == currentEmail ? .success(()) : .failure(.mismatchEmail)
			}

		// Aggregate latest failure contexts as a stream of strings.
		reasons = Property.combineLatest(email.result, emailConfirmation.result)
			.signal
			.map { [$0, $1].flatMap { $0.error?.reason }.joined(separator: "\n") }

		// A `Property` of the validated username.
		//
		// It outputs the valid username for the `Action` to work on, or `nil` if the form
		// is invalid and the `Action` would be disabled consequently.
		let validatedUsername = Property.combineLatest(email.result,
		                                               emailConfirmation.result,
		                                               termsAccepted)
			.map { !$0.isFailure && !$1.isFailure && $2 }
			.combineLatest(with: username)
			.map { isValid, username in isValid ? username : nil }

		// The action to be invoked when the submit button is pressed.
		// It enables only if all the controls have passed their validations.
		submit = Action(input: validatedUsername) { username in
			return userService.canUseUsername(username)
				.promoteErrors(FormError.self)
				.attemptMap { Result<(), FormError>($0 ? () : nil, failWith: .usernameUnavailable) }
		}
	}
}

final class ViewController: UIViewController {
	private let viewModel: ViewModel
	private var formView: FormView!

	override func viewDidLoad() {
		super.viewDidLoad()

		// Initialize the interactive controls.
		formView.emailField.text = viewModel.email.commitedValue
		formView.emailConfirmationField.text = viewModel.emailConfirmation.commitedValue
		formView.termsSwitch.isOn = false

		// Setup bindings with the interactive controls.
		viewModel.email <~ formView.emailField.reactive
			.continuousTextValues.skipNil()

		viewModel.emailConfirmation <~ formView.emailConfirmationField.reactive
			.continuousTextValues.skipNil()

		viewModel.termsAccepted <~ formView.termsSwitch.reactive
			.isOnValues

		// Setup bindings with the invalidation reason label.
		formView.reasonLabel.reactive.text <~ viewModel.reasons

		// Setup the Action binding with the submit button.
		formView.submitButton.reactive.pressed = CocoaAction(viewModel.submit)
	}

	override func loadView() {
		formView = FormView()
		view = formView
	}

	init(_ viewModel: ViewModel) {
		self.viewModel = viewModel
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}

final class UserService {
	func canUseUsername(_ string: String) -> SignalProducer<Bool, NoError> {
		return SignalProducer { observer, disposable in
			observer.send(value: true)
			observer.sendCompleted()
		}
	}
}

func main() {
	let userService = UserService()
	let viewModel = ViewModel(userService: userService)
	let viewController = ViewController(viewModel)
	let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 350))
	window.rootViewController = viewController

	PlaygroundPage.current.liveView = window
	PlaygroundPage.current.needsIndefiniteExecution = true

	window.makeKeyAndVisible()

	// Setup console messages.
	viewModel.submit.values.observeValues {
		print("ViewModel.submit: Username `\($0)`.")
	}

	viewModel.submit.completed.observeValues {
		print("ViewModel.submit: execution producer has completed.")
	}

	viewModel.email.result.signal.observeValues {
		print("ViewModel.email: Validation result - \($0 != nil ? "\($0!)" : "No validation has ever been performed.")")
	}

	viewModel.emailConfirmation.result.signal.observeValues {
		print("ViewModel.emailConfirmation: Validation result - \($0 != nil ? "\($0!)" : "No validation has ever been performed.")")
	}
}

main()
