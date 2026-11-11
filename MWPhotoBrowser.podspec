Pod::Spec.new do |s|

  s.name = 'MWPhotoBrowser'
  s.version = '2.1.2'
  s.license = 'MIT'
  s.summary = 'A simple iOS photo and video browser with optional grid view, captions and selections.'
  s.description = <<-DESCRIPTION
                  MWPhotoBrowser can display one or more images or videos by providing either UIImage
                  objects, PHAsset objects, or URLs to library assets, web images/videos or local files.
                  The photo browser handles the downloading and caching of photos from the web seamlessly.
                  Photos can be zoomed and panned, and optional (customisable) captions can be displayed.
                  DESCRIPTION

  s.homepage = 'https://github.com/Gatnnj/MWPhotoBrowser.git'
  s.author = { 'Gatnnj' => 'gatnnj880@gmail.com' }

  s.source = {
    :git => 'https://github.com/Gatnnj/MWPhotoBrowser.git',
    :tag => '2.1.2'
  }
  s.platform = :ios, '13.0'
  s.source_files = 'Pod/Classes/**/*'
  # 图标统一收进 asset catalog：打包时由 actool 编译进 MWPhotoBrowser.bundle 的 Assets.car。
  # 好处是只保留一份源文件、自动匹配 @1x/@2x/@3x、支持 App Thinning / Dark Mode，
  # 并且资源名被限定在库自己的 bundle 里，不会和宿主 app 的同名图片冲突。
  s.resource_bundles = {
    'MWPhotoBrowser' => ['Pod/Assets/*.xcassets']
  }
  s.requires_arc = true

  # AssetsLibrary、MediaPlayer 已移除（iOS 9 废弃），
  # 替换为视频所需的 AVKit/AVFoundation，Photos 由弱框架改为强依赖
  s.frameworks = 'ImageIO', 'QuartzCore', 'AVKit', 'AVFoundation', 'Photos'

  # SDWebImage
  # 3.7.2 contains bugs downloading local files
  # https://github.com/rs/SDWebImage/issues/1109
  s.dependency 'SDWebImage', '>= 5.0.0'

end
