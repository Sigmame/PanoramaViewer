import Foundation
import Photos
import UIKit

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
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        
        let scale = UIScreen.main.scale
        let targetWidth: CGFloat = 400 * scale
        let targetHeight: CGFloat = 200 * scale
        
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: targetWidth, height: targetHeight),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }
    
    func loadFullResolutionImage(for asset: PHAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        imageManager.requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
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
        ) { avAsset, _, _ in
            if let urlAsset = avAsset as? AVURLAsset {
                completion(urlAsset.url)
            } else {
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