Pod::Spec.new do |s|
  s.name             = 'Harbor'
  s.version          = '3.0.0'
  s.summary          = 'Networking library.'
  s.homepage         = 'https://github.com/javiermanzo/Harbor'
  s.license          = { :type => 'MIT', :file => 'LICENSE.md' }
  s.author           = { 'Javier Manzo' => 'javier.r.manzo@gmail.com' }
  s.source           = { :git => 'https://github.com/javiermanzo/Harbor.git', :tag => s.version.to_s }
  s.social_media_url = 'https://www.linkedin.com/in/javiermanzo/'
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.0'
  s.source_files = 'Sources/Harbor/**/*'

  s.dependency 'LogBird', '1.0'
end
