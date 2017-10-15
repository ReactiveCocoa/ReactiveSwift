/*:
 > # IMPORTANT: To use `ReactiveSwift.playground`, please:
 
 1. Retrieve the project dependencies using one of the following terminal commands from the ReactiveSwift project root directory:
    - `git submodule update --init`
 **OR**, if you have [Carthage](https://github.com/Carthage/Carthage) installed
    - `carthage checkout --no-use-binaries`
 1. Open `ReactiveSwift.xcworkspace`
 1. Build `Result-Mac` scheme
 1. Build `ReactiveSwift-macOS` scheme
 1. Finally open the `ReactiveSwift.playground`
 1. Choose `View > Show Debug Area`
 */

import Result
import ReactiveSwift
import Foundation

/*:
 ## Sandbox
 
 A place where you can build your sand castles 🏖.
*/
public struct InvalidInput: Error {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

extension EditingProperty.Validation where ValidationError == InvalidInput {
    public static func none<U>(_ keyPath: WritableKeyPath<Value, U>) -> EditingProperty.Validation {
        return EditingProperty.Validation(for: keyPath, validate: { _ in nil })
    }

    public static func mandatory(_ keyPath: WritableKeyPath<Value, String>, _ reason: String) -> EditingProperty.Validation {
        return EditingProperty.Validation(for: keyPath, validate: { $0.isEmpty ? InvalidInput(reason: reason) : nil })
    }

    public static func mandatory(_ keyPath: WritableKeyPath<Value, String?>, _ reason: String) -> EditingProperty.Validation {
        return EditingProperty.Validation(for: keyPath, validate: { ($0?.isEmpty ?? true) ? InvalidInput(reason: reason) : nil })
    }

    public static func custom<U>(_ keyPath: WritableKeyPath<Value, U>, _ predicate: @escaping (U) -> Bool, _ reason: String) -> EditingProperty.Validation {
        return EditingProperty.Validation(for: keyPath, validate: { !predicate($0) ? InvalidInput(reason: reason) : nil })
    }
}

struct User {
    var firstName: String = ""
    var lastName: String = ""
    var phoneNumber: String = ""
}

let user = EditingProperty<User, InvalidInput>(User(), validations: [
    .mandatory(\.firstName, "First name is mandatory."),
    .mandatory(\.lastName, "Last name is mandatory."),
    .custom(\.phoneNumber, { $0.hasPrefix("+44") }, "Phone number is not a UK number."),
])

print("(1)")
user.validated.producer.startWithValues { result in
    switch result {
    case let .success(value):
        print("SUCCESS: \(value)")
    case let .failure(error):
        print("FAILURE: \(error.errors.map { $0.reason })")
    }
}
// FAILURE: ["First name is mandatory.", "Phone number is not a UK number.", "Last name is mandatory."]

print("(2)")
user[\.firstName] <~ SignalProducer(value: "Steve")
// FAILURE: ["Phone number is not a UK number.", "Last name is mandatory."]

print("(3)")
user[\.lastName] <~ SignalProducer(value: "Jobs")
// FAILURE: ["Phone number is not a UK number."]

print("(4)")
user[\.phoneNumber] <~ SignalProducer(value: "+00")
// FAILURE: ["Phone number is not a UK number."]

print("(5)")
user[\.phoneNumber] <~ SignalProducer(value: "+44")
// SUCCESS: User(firstName: "Steve", lastName: "Jobs", phoneNumber: "+44")

print("(5)")
user[\.phoneNumber] <~ SignalProducer(value: "")
// FAILURE: ["Phone number is not a UK number."]
