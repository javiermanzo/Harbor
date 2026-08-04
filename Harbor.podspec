Pod::Spec.new do |s|
  s.name             = 'Harbor'
  s.version          = '3.1.0'
  s.summary          = 'Networking library.'
  s.homepage         = 'https://github.com/javiermanzo/Harbor'
  s.license          = { :type => 'MIT', :file => 'LICENSE.md' }
  s.author           = { 'Javier Manzo' => 'javier.r.manzo@gmail.com' }
  s.source           = { :git => 'https://github.com/javiermanzo/Harbor.git', :tag => s.version.to_s }
  s.social_media_url = 'https://www.linkedin.com/in/javiermanzo/'
  s.ios.deployment_target = '15.0'
  s.swift_version = '6.0'
  s.default_subspecs = 'Core'

  s.dependency 'LogBird', '2.1.0'

  s.subspec 'Core' do |core|
    core.source_files = 'Sources/Harbor/**/*.swift'
  end

  s.subspec 'JRPC' do |j|
    j.source_files = 'Sources/HarborJRPC/**/*.swift'
    j.dependency 'Harbor/Core'
  end
end
