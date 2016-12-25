import UIKit
import ReactiveSwift
import Result

public class FormView: UIView {
	let _lifetime = Lifetime.Token()
	lazy var lifetime: Lifetime = Lifetime(self._lifetime)

	public var emailValues: Signal<String?, NoError> {
		return Signal { observer in
			let target = Target { observer.send(value: ($0 as! UITextField).text) }
			emailField.addTarget(target, action: #selector(target.execute), for: .editingChanged)
			return ActionDisposable { _ = target }
		}
	}

	public var emailConfirmationValues: Signal<String?, NoError> {
		return Signal { observer in
			let target = Target { observer.send(value: ($0 as! UITextField).text) }
			emailConfirmationField.addTarget(target, action: #selector(target.execute), for: .editingChanged)
			return ActionDisposable { _ = target }
		}
	}

	public var termsAccepted: Signal<Bool, NoError> {
		return Signal { observer in
			let target = Target { observer.send(value: ($0 as! UISwitch).isOn) }
			termsSwitch.addTarget(target, action: #selector(target.execute), for: .valueChanged)
			return ActionDisposable { _ = target }
		}
	}

	public var invalidationReasons: BindingTarget<String> {
		return BindingTarget(lifetime: lifetime) { [weak reasonLabel] value in
			reasonLabel?.text = value
		}
	}

	private let disposable = SerialDisposable()

	public var submit: Action<(), String, NoError>? {
		didSet {
			if let action = submit {
				let target = Target { _ in action.apply().start() }
				submitButton.addTarget(target, action: #selector(target.execute), for: .touchUpInside)
				let disposable = CompositeDisposable()
				disposable += action.lifetime.ended.observeCompleted { _ = target }
				disposable += action.isEnabled.producer
					.startWithValues { [weak submitButton] in submitButton?.isEnabled = $0 }
				self.disposable.inner = disposable
			} else {
				disposable.inner = nil
			}
		}
	}

	public let emailField = UITextField()
	public let emailConfirmationField = UITextField()
	public let termsSwitch = UISwitch()
	public let submitButton = UIButton(type: .system)
	public let reasonLabel = UILabel()

	convenience init() {
		self.init(frame: CGRect(x: 0, y: 0, width: 300, height: 300))

		backgroundColor = .white

		addSubview(emailField)
		addSubview(emailConfirmationField)
		addSubview(termsSwitch)
		addSubview(submitButton)
		addSubview(reasonLabel)

		let labelFont = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)

		// Email Field.
		let emailLabel = UILabel(frame: CGRect(x: 20, y: 20, width: 260, height: 20))
		emailLabel.font = labelFont
		emailLabel.text = "E-mail"
		addSubview(emailLabel)

		emailField.borderStyle = .roundedRect
		emailField.frame.origin = CGPoint(x: 20, y: 40)
		emailField.frame.size = CGSize(width: 260, height: 30)

		// Email Confirmation Field.
		let emailConfirmationLabel = UILabel(frame: CGRect(x: 20, y: 80, width: 260, height: 20))
		emailConfirmationLabel.font = labelFont
		emailConfirmationLabel.text = "Confirm E-mail"
		addSubview(emailConfirmationLabel)

		emailConfirmationField.borderStyle = .roundedRect
		emailConfirmationField.frame.origin = CGPoint(x: 20, y: 100)
		emailConfirmationField.frame.size = CGSize(width: 260, height: 30)

		// Accept Terms Switch
		let termsSwitchLabel = UILabel(frame: CGRect(x: 80, y: 155, width: 200, height: 20))
		termsSwitchLabel.font = labelFont
		termsSwitchLabel.text = "Accept Terms and Conditions"
		addSubview(termsSwitchLabel)

		termsSwitch.frame.origin = CGPoint(x: 20, y: 150)

		// Submit Button
		submitButton.titleLabel!.font = labelFont
		submitButton.setBackgroundColor(submitButton.tintColor, for: .normal)
		submitButton.setBackgroundColor(UIColor(white: 0.85, alpha: 1.0), for: .disabled)
		submitButton.setTitleColor(.white, for: .normal)
		submitButton.setTitle("Submit", for: .normal)
		submitButton.frame.origin = CGPoint(x: 20, y: 200)
		submitButton.frame.size = CGSize(width: 260, height: 30)

		// Reason Label
		reasonLabel.frame.origin = CGPoint(x: 20, y: 250)
		reasonLabel.frame.size = CGSize(width: 260, height: 30)
		reasonLabel.numberOfLines = 0
		reasonLabel.font = labelFont
	}
}

// http://stackoverflow.com/questions/26600980/how-do-i-set-uibutton-background-color-forstate-uicontrolstate-highlighted-in-s
extension UIButton {
	func setBackgroundColor(_ color: UIColor, for state: UIControlState) {
		UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
		let context = UIGraphicsGetCurrentContext()!
		context.setFillColor(color.cgColor)
		context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
		let colorImage = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()
		self.setBackgroundImage(colorImage, for: state)
	}
}
