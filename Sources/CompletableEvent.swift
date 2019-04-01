/// Event protocol with completed case.
public protocol CompletableEventProtocol: GEventProtocol {
	static var completedCase: Self { get }
}

/// Event with completed case.
public enum CompletableEvent: CompletableEventProtocol {
	case completed
	case interrupted

	public var isTerminating: Bool { return true }

	public static var completedCase: CompletableEvent {
		return .completed
	}

	public static var interruptedCase: CompletableEvent {
		return .interrupted
	}
}
