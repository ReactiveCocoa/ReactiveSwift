import Foundation

class Target {
	let action: (Any) -> Void

	init(_ action: @escaping (Any) -> Void) {
		self.action = action
	}

	@objc func execute(_ sender: Any) {
		action(sender)
	}
}
