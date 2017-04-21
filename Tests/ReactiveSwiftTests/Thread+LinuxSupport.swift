#if os(Linux)
	import Foundation
	import func CoreFoundation._CFIsMainThread

	extension Thread {
		// `isMainThread` is not implemented yet in swift-corelibs-foundation.
		internal static var isMainThread: Bool {
			return _CFIsMainThread()
		}
	}
#endif
