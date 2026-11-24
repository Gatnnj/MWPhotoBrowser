Pod::Spec.new do |s|

  s.name = 'MWPhotoBrowser'
  s.version = '3.2.0'
  s.license = 'MIT'
  s.summary = '一个经过重生的iOS图片浏览器，最低支持iOS15.0'
  s.description = <<-DESCRIPTION
                  MWPhotoBrowser 经过涅槃重生，适配了最低iOS15.0，并且增加拖拽交互关闭，优化了展示缩略图内存，按可用剩余内存预加载。
                  增加文档开关模糊展示图片。
                  DESCRIPTION

  s.homepage = 'https://github.com/Gatnnj/MWPhotoBrowser.git'
  s.author = { 'Gatnnj' => 'gatnnj880@gmail.com' }

  s.source = {
    :git => 'https://github.com/Gatnnj/MWPhotoBrowser.git',
    :tag => s.version.to_s
  }
  s.platform = :ios, '15.0'
  s.source_files = 'Pod/Classes/**/*'
  # 与 Package.swift 共用同一份源码与资源；SPM 侧产物为 MWPhotoBrowser_MWPhotoBrowser.bundle
  # 图标统一收进 asset catalog：打包时由 actool 编译进 MWPhotoBrowser.bundle 的 Assets.car。
  # 好处是只保留一份源文件、自动匹配 @1x/@2x/@3x、支持 App Thinning / Dark Mode，
  # 并且资源名被限定在库自己的 bundle 里，不会和宿主 app 的同名图片冲突。
  s.resource_bundles = {
    'MWPhotoBrowser' => ['Pod/Assets/*.xcassets', 'Pod/Assets/PrivacyInfo.xcprivacy']
  }
  s.requires_arc = true
  s.frameworks = 'ImageIO', 'QuartzCore', 'Photos'

  # SDWebImage
  # 3.7.2 contains bugs downloading local files
  # https://github.com/rs/SDWebImage/issues/1109
  s.dependency 'SDWebImage', '>= 5.0.0'

end
