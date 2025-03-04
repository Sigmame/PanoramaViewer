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
    
    func loadFullResolutionImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.version = .current
        
        // 计算合适的目标尺寸，确保不超过 Metal 的纹理限制
        let maxTextureSize: CGFloat = 16384
        let aspectRatio = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
        let targetSize: CGSize
        
        if CGFloat(asset.pixelWidth) > maxTextureSize || CGFloat(asset.pixelHeight) > maxTextureSize {
            // 如果任一维度超过限制，按比例缩放
            if aspectRatio > 1 {
                let width = min(CGFloat(asset.pixelWidth), maxTextureSize)
                let height = width / aspectRatio
                targetSize = CGSize(width: width, height: height)
            } else {
                let height = min(CGFloat(asset.pixelHeight), maxTextureSize)
                let width = height * aspectRatio
                targetSize = CGSize(width: width, height: height)
            }
            print("⚠️ Image exceeds Metal texture size limit, scaling down to: \(targetSize)")
        } else {
            targetSize = CGSize(width: CGFloat(asset.pixelWidth), height: CGFloat(asset.pixelHeight))
            print("📐 Loading image with original size: \(targetSize)")
        }
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            if let error = info?[PHImageErrorKey] as? Error {
                print("❌ Error loading image: \(error)")
            } else if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
                print("⚠️ Received degraded image")
            }
            completion(image)
        }
    }
    
    func loadVideo(for asset: PHAsset, completion: @escaping (URL?) -> Void) {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        imageManager.requestAVAsset(
            forVideo: asset,
            options: options
        ) { avAsset, audioMix, info in
            if let urlAsset = avAsset as? AVURLAsset {
                // 检查原始视频的文件扩展名，确保使用正确的扩展名
                let originalExtension = urlAsset.url.pathExtension.lowercased()
                let fileExtension = originalExtension.isEmpty ? "mp4" : originalExtension
                
                // 仅使用临时目录，而不是应用的文档目录
                let tempDirectory = FileManager.default.temporaryDirectory
                let uniqueFileName = UUID().uuidString + "." + fileExtension
                var localURL = tempDirectory.appendingPathComponent(uniqueFileName)
                
                do {
                    // 如果已存在同名文件，先删除
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        try FileManager.default.removeItem(at: localURL)
                    }
                    
                    print("🎥 准备复制视频文件: \(urlAsset.url.lastPathComponent) -> \(localURL.lastPathComponent)")
                    
                    // 复制视频文件到临时目录
                    try FileManager.default.copyItem(at: urlAsset.url, to: localURL)
                    
                    // 设置文件权限为所有用户可读写，这对AirDrop非常重要
                    try FileManager.default.setAttributes([
                        .posixPermissions: 0o644
                    ], ofItemAtPath: localURL.path)
                    
                    // 设置文件属性，确保不会包含在备份中
                    var resourceValues = URLResourceValues()
                    resourceValues.isExcludedFromBackup = true
                    try localURL.setResourceValues(resourceValues)
                    
                    // 添加额外的UTI类型提示 - 使用contentType而不是typeIdentifier
                    if fileExtension == "mov" {
                        try localURL.setResourceValues(URLResourceValues(dictionary: [
                            .contentTypeKey: UTType.quickTimeMovie
                        ]))
                    } else if fileExtension == "mp4" {
                        try localURL.setResourceValues(URLResourceValues(dictionary: [
                            .contentTypeKey: UTType.mpeg4Movie
                        ]))
                    }
                    
                    // 验证文件是否可访问
                    let isReadable = FileManager.default.isReadableFile(atPath: localURL.path)
                    print(isReadable ? "✅ 视频文件可读" : "⚠️ 视频文件不可读")
                    
                    // 检查文件大小
                    let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
                    if let fileSize = attributes[.size] as? UInt64 {
                        print("📊 视频文件大小: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))")
                    }
                    
                    if let posixPermissions = attributes[.posixPermissions] as? NSNumber {
                        print("🔑 文件权限: \(String(format: "%o", posixPermissions.intValue))")
                    }
                    
                    // 返回本地URL
                    completion(localURL)
                } catch {
                    print("❌ 创建本地视频副本失败: \(error.localizedDescription)")
                    completion(nil)
                }
            } else {
                print("❌ 无法获取视频资源")
                completion(nil)
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