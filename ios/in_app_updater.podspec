#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint in_app_updater.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'in_app_updater'
  s.version          = '0.0.1'
  s.summary          = "Prompt users to update via Google Play's In-App Update API on Android and an App Store lookup + StoreKit sheet on iOS."
  s.description      = <<-DESC
Prompt users to update via Google Play's In-App Update API on Android and an
App Store lookup + StoreKit sheet on iOS.
                       DESC
  s.homepage         = 'https://github.com/dhirajved/in_app_updater'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Dhiraj Ved' => 'rathoddhiraj8000@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'in_app_updater/Sources/in_app_updater/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'in_app_updater_privacy' => ['in_app_updater/Sources/in_app_updater/PrivacyInfo.xcprivacy']}
end
