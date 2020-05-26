Pod::Spec.new do |s|
  s.name         = "ReactiveSwift"
  # Version goes here and will be used to access the git tag later on, once we have a first release.
  s.version      = "6.3.0"
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
  # Directory glob for all Swift files
  s.source_files  = "Sources/*.{swift}"

  s.pod_target_xcconfig = {"OTHER_SWIFT_FLAGS[config=Release]" => "$(inherited) -suppress-warnings" }

  s.cocoapods_version = ">= 1.7.0"
  s.swift_versions = ["5.0", "5.1"]
end
