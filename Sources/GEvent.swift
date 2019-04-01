/// Generalized event.
public protocol GEventProtocol {
	var isTerminating: Bool { get }

	/// - Todo: This could be separated into another protocol.
	static var interruptedCase: Self { get }
}
