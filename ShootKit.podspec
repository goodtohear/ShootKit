Pod::Spec.new do |s|
  s.name             = 'ShootKit'
  s.version          = '1.1.0'
  s.summary          = 'Talk to Shoot cameras and Video Pencil from your Mac app.'
  s.description      = <<-DESC
    ShootKit provides a Swift and Objective-C API for integrating Shoot camera
    control and Video Pencil overlays into macOS apps. Handles Bonjour
    discovery, HEVC encoding/decoding, and remote camera control commands over
    the local network.
  DESC

  s.homepage         = 'https://github.com/goodtohear/ShootKit'
  s.license          = { :type => 'MIT', :file => 'ShootKit/LICENSE' }
  s.author           = { 'Michael Forrest' => 'michael.forrest@gmail.com' }
  s.source           = { :git => 'https://github.com/goodtohear/ShootKit.git', :tag => s.version.to_s }

  s.osx.deployment_target = '12.0'
  s.swift_versions        = ['5.0']

  s.source_files = 'ShootKit/ShootKit/Sources/**/*.swift'

  s.frameworks = 'Foundation', 'AppKit', 'AVFoundation', 'CoreImage', 'CoreMedia', 'Network', 'VideoToolbox'
end
