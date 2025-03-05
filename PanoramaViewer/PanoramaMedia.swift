import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

enum MediaType {
    case image
    case video
}

struct PanoramaMedia: Identifiable {
    let id = UUID()
    let asset: PHAsset
    let type: MediaType
    var thumbnail: UIImage?
    
    static func isPanorama(asset: PHAsset) -> Bool {
        return asset.pixelWidth == asset.pixelHeight * 2
    }
}

class PanoramaMediaManager: NSObject, ObservableObject {
    @Published var panoramaMedia: [PanoramaMedia] = []
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    private let imageManager = PHImageManager.default()
    
    override init() {
        super.init()
        checkAuthorization()
    }
    
    private func checkAuthorization() {
        DispatchQueue.main.async {
            self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if self.authorizationStatus == .notDetermined {
                self.requestAuthorization()
            } else if self.authorizationStatus == .authorized || self.authorizationStatus == .limited {
                self.fetchPanoramaMedia()
                self.startLibraryObserver()
            }
        }
    }
    
    func requestAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                if status == .authorized || status == .limited {
                    self?.fetchPanoramaMedia()
                    self?.startLibraryObserver()
                }
            }
        }
    }
    
    private func startLibraryObserver() {
        PHPhotoLibrary.shared().register(self)
    }
    
    func fetchPanoramaMedia() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }
        
        let imageOptions = PHFetchOptions()
        imageOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        imageOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        imageOptions.includeAssetSourceTypes = .typeUserLibrary
        
        let videoOptions = PHFetchOptions()
        videoOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        videoOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        videoOptions.includeAssetSourceTypes = .typeUserLibrary
        
        let allImages = PHAsset.fetchAssets(with: .image, options: imageOptions)
        let allVideos = PHAsset.fetchAssets(with: .video, options: videoOptions)
        var newPanoramaMedia: [PanoramaMedia] = []
        
        // 处理图片
        allImages.enumerateObjects { (asset, _, _) in
            if PanoramaMedia.isPanorama(asset: asset) {
                let media = PanoramaMedia(asset: asset, type: .image)
                newPanoramaMedia.append(media)
                self.loadThumbnail(for: asset) { thumbnail in
                    if let index = self.panoramaMedia.firstIndex(where: { $0.id == media.id }) {
                        DispatchQueue.main.async {
                            self.panoramaMedia[index].thumbnail = thumbnail
                        }
                    }
                }
            }
        }
        
        // 处理视频
        allVideos.enumerateObjects { (asset, _, _) in
            if PanoramaMedia.isPanorama(asset: asset) {
                let media = PanoramaMedia(asset: asset, type: .video)
                newPanoramaMedia.append(media)
                self.loadThumbnail(for: asset) { thumbnail in
                    if let index = self.panoramaMedia.firstIndex(where: { $0.id == media.id }) {
                        DispatchQueue.main.async {
                            self.panoramaMedia[index].thumbnail = thumbnail
                        }
                    }
                }
            }
        }
        
        // 按创建时间降序排序合并后的媒体列表
        newPanoramaMedia.sort { (media1, media2) -> Bool in
            let date1 = media1.asset.creationDate ?? Date.distantPast
            let date2 = media2.asset.creationDate ?? Date.distantPast
            return date1 > date2
        }
        
        DispatchQueue.main.async {
            self.panoramaMedia = newPanoramaMedia
        }
    }
    
    private func loadThumbnail(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        options.isSynchronous = false
        options.version = .current
        
        // 计算合适的目标尺寸，确保不超过 Metal 的纹理限制
        let maxTextureSize: CGFloat = 16384
        let aspectRatio = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
        let targetSize: CGSize
        
        if CGFloat(asset.pixelWidth) > maxTextureSize {
            let width = min(320, maxTextureSize)
            let height = width / aspectRatio
            targetSize = CGSize(width: width, height: height)
            print("🔍 Scaling down thumbnail to: \(targetSize)")
        } else {
            targetSize = CGSize(width: min(320, CGFloat(asset.pixelWidth)), 
                              height: min(160, CGFloat(asset.pixelHeight)))
        }
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            if let error = info?[PHImageErrorKey] as? Error {
                print("❌ Error loading thumbnail: \(error)")
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
    
    func loadFullResolutionImage(for asset: PHAsset, completion: @escaping (URL?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.version = .current
        
        print("🖼 开始加载图片资源")
        print("  - Asset ID: \(asset.localIdentifier)")
        print("  - 尺寸: \(asset.pixelWidth)x\(asset.pixelHeight)")
        print("  - 创建时间: \(asset.creationDate?.description ?? "unknown")")
        
        // 获取原始图片数据
        let imageRequestOptions = PHImageRequestOptions()
        imageRequestOptions.deliveryMode = .highQualityFormat
        imageRequestOptions.isNetworkAccessAllowed = true
        imageRequestOptions.version = .current
        imageRequestOptions.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: imageRequestOptions) { (data, uti, orientation, info) in
            print("\n📥 图片数据回调:")
            print("  - UTI: \(uti ?? "unknown")")
            print("  - Orientation: \(orientation.rawValue)")
            
            if let degraded = info?[PHImageResultIsDegradedKey] as? Bool {
                print("  - Is Degraded: \(degraded)")
            }
            
            if let error = info?[PHImageErrorKey] as? Error {
                print("❌ 加载错误: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            guard let imageData = data else {
                print("❌ 无法获取图片数据")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            print("🖼 获取到图片数据: \(ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file))")
            
            // 使用 Documents 目录
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            
            // 根据 UTI 确定文件扩展名
            let fileExtension: String
            if let uti = uti {
                if uti.contains("jpeg") || uti.contains("jpg") {
                    fileExtension = "jpg"
                } else if uti.contains("png") {
                    fileExtension = "png"
                } else if uti.contains("heic") {
                    fileExtension = "heic"
                } else {
                    fileExtension = "jpg"  // 默认使用 jpg
                }
            } else {
                fileExtension = "jpg"
            }
            
            let localURL = documentsDir.appendingPathComponent("share_" + UUID().uuidString + "." + fileExtension)
            print("\n📁 准备创建文件:")
            print("  - 路径: \(localURL.path)")
            print("  - 扩展名: \(fileExtension)")
            
            do {
                // 如果文件已存在，先删除
                if FileManager.default.fileExists(atPath: localURL.path) {
                    try FileManager.default.removeItem(at: localURL)
                    print("🗑 删除已存在的文件")
                }
                
                // 保存图片数据到文件
                try imageData.write(to: localURL)
                print("✅ 文件创建成功")
                
                // 设置文件权限为所有用户可读写
                try FileManager.default.setAttributes([
                    .posixPermissions: 0o644
                ], ofItemAtPath: localURL.path)
                print("✅ 文件权限设置成功")
                
                // 验证文件状态
                let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
                print("\n📄 文件状态:")
                print("  - 大小: \(ByteCountFormatter.string(fromByteCount: Int64(attributes[.size] as? UInt64 ?? 0), countStyle: .file))")
                print("  - 权限: \(String(format: "%o", attributes[.posixPermissions] as? Int ?? 0))")
                print("  - 创建时间: \(attributes[.creationDate] as? Date ?? Date())")
                print("  - 所有者: \(attributes[.ownerAccountName] as? String ?? "unknown")")
                print("  - 可读: \(FileManager.default.isReadableFile(atPath: localURL.path))")
                print("  - 可写: \(FileManager.default.isWritableFile(atPath: localURL.path))")
                
                DispatchQueue.main.async {
                    completion(localURL)
                }
            } catch {
                print("\n❌ 文件操作失败:")
                print("  - 错误: \(error.localizedDescription)")
                if let nsError = error as? NSError {
                    print("  - Domain: \(nsError.domain)")
                    print("  - Code: \(nsError.code)")
                    print("  - Description: \(nsError.localizedDescription)")
                    print("  - Failure Reason: \(nsError.localizedFailureReason ?? "unknown")")
                    print("  - Recovery Suggestion: \(nsError.localizedRecoverySuggestion ?? "unknown")")
                }
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    func loadVideo(for asset: PHAsset, completion: @escaping (URL?) -> Void) {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        print("🎥 开始加载视频资源")
        imageManager.requestAVAsset(
            forVideo: asset,
            options: options
        ) { avAsset, audioMix, info in
            if let urlAsset = avAsset as? AVURLAsset {
                print("🎥 获取到视频资源URL: \(urlAsset.url.lastPathComponent)")
                
                // 使用 Documents 目录而不是临时目录
                let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let originalExtension = urlAsset.url.pathExtension.isEmpty ? "mp4" : urlAsset.url.pathExtension
                let localURL = documentsDir.appendingPathComponent("share_" + UUID().uuidString + "." + originalExtension)
                
                do {
                    // 如果文件已存在，先删除
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        try FileManager.default.removeItem(at: localURL)
                        print("🗑 删除已存在的文件")
                    }
                    
                    // 复制文件
                    try FileManager.default.copyItem(at: urlAsset.url, to: localURL)
                    print("📁 创建文件副本: \(localURL.lastPathComponent)")
                    
                    // 设置文件权限为所有用户可读写
                    try FileManager.default.setAttributes([
                        .posixPermissions: 0o644
                    ], ofItemAtPath: localURL.path)
                    
                    // 验证文件状态
                    let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
                    print("📄 文件状态:")
                    print("  - 大小: \(ByteCountFormatter.string(fromByteCount: Int64(attributes[.size] as? UInt64 ?? 0), countStyle: .file))")
                    print("  - 权限: \(String(format: "%o", attributes[.posixPermissions] as? Int ?? 0))")
                    print("  - 可读: \(FileManager.default.isReadableFile(atPath: localURL.path))")
                    
                    DispatchQueue.main.async {
                        completion(localURL)
                    }
                } catch {
                    print("❌ 创建文件失败: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            } else {
                print("❌ 无法获取视频资源")
                if let error = info?[PHImageErrorKey] as? Error {
                    print("  - 错误信息: \(error.localizedDescription)")
                }
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}

extension PanoramaMediaManager: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            self.fetchPanoramaMedia()
        }
    }
} 