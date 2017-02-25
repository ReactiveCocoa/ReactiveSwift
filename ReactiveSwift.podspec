Pod::Spec.new do |s|
  s.name         = "ReactiveSwift"
  # Version goes here and will be used to access the git tag later on, once we have a first release.
  s.version      = "1.1.0"
  s.summary      = "Streams of values over time"
  s.description  = <<-DESC
                   ReactiveSwift is a Swift framework inspired by Functional Reactive Programming. It provides APIs for composing and transforming streams of values over time.
                   DESC
  s.homepage     = "https://github.com/ReactiveCocoa/ReactiveSwift"
  s.license      = { :type => "MIT", :file => "LICENSE.md" }
  s.author       = "ReactiveCocoa"

  s.ios.deployment_target = "8.0"
  s.osx.deployment_target = "10.9"
  s.watchos.deployment_target = "2.0"
  s.tvos.deployment_target = "9.0"
  s.source       = { :git => "https://github.com/ReactiveCocoa/ReactiveSwift.git", :tag => "#{s.version}" }
  s.public_header_files = "Sources/ReactiveSwift/ReactiveSwift.h"
  s.private_header_files = "Sources/OSLocking/include/*.{h}"
  s.module_map = "Sources/ReactiveSwift/module.modulemap"

  # Directory glob for all Swift files
  s.source_files  = "Sources/ReactiveSwift/*.{swift,h}", "Sources/OSLocking/*.{c}", "Sources/OSLocking/include/*.{h}"
  s.dependency 'Result', '~> 3.1'

  s.pod_target_xcconfig = {"OTHER_SWIFT_FLAGS[config=Release]" => "-suppress-warnings" }
end
