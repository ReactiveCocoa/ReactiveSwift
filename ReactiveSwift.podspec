Pod::Spec.new do |s|
  s.name         = "ReactiveSwift"
  s.version      = "0.0.1"
  s.summary      = "Streams of values over time"
  s.description  = <<-DESC
                   ReactiveSwift is a Swift framework inspired by Functional Reactive Programming. It provides APIs for composing and transforming streams of values over time.
                   DESC
  s.homepage     = "https://github.com/ReactiveCocoa/ReactiveSwift"
  s.license      = { :type => "MIT", :file => "LICENSE.md" }
  s.author       = "ReactiveCocoa"
  
  s.ios.deployment_target = "8.0"
  s.osx.deployment_target = "10.10"
  s.watchos.deployment_target = "2.0"
  s.tvos.deployment_target = "9.0"
  s.source       = { :git => "https://github.com/ReactiveCocoa/ReactiveSwift.git", :commit => "2cdbc4159dede57a47df0e2eeccd8c0ba8436470" }
  s.source_files  = "Sources/*.{swift}"
  s.dependency 'Result', '~> 3.0'
end
