Pod::Spec.new do |s|
  s.name             = 'conduit_home'
  s.version          = '0.1.0'
  s.summary          = 'Home build: system-browser sheet for the Keycloak sign-in.'
  s.description      = <<-DESC
  ASWebAuthenticationSession bridge for the home build's PKCE login (OWU-157).
  DESC
  s.homepage         = 'https://github.com/pocharlies-org/conduit'
  s.license          = { :file => '../../../LICENSE' }
  s.author           = { 'pocharlies' => 'me@e-dani.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '16.0'
  s.swift_version    = '5.0'
  s.dependency 'Flutter'
  s.static_framework = true
end
