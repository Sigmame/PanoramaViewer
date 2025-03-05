//
//  ContentView.swift
//  PanoramaViewer
//
//  Created by sigma on 2024/12/27.
//

import SwiftUI
import PhotosUI
import SceneKit
import UIKit
import AVFoundation
import UniformTypeIdentifiers
import SpriteKit
import Metal
import QuartzCore

// MARK: - PanoramaView
struct PanoramaView: UIViewRepresentable {
    let image: UIImage
    
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        let scene = SCNScene()
        
        // 创建相机节点
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 80  // 设置初始FOV为80度
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 0)
        scene.rootNode.addChildNode(cameraNode)
        
        // 创建球体 - 使用更高的细分度以获得更好的渲染效果
        let sphere = SCNSphere(radius: 10)
        sphere.segmentCount = 96  // 增加球体的细分度
        
        // 创建并配置材质
        let material = SCNMaterial()
        
        // 处理图片尺寸，确保不超过Metal纹理限制
        let maxTextureSize: CGFloat = 16384
        let processedImage: UIImage
        
        if image.size.width > maxTextureSize || image.size.height > maxTextureSize {
            let scale = min(maxTextureSize / image.size.width, maxTextureSize / image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            processedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
            
            print("⚠️ Image resized from \(image.size) to \(processedImage.size) due to Metal texture size limit")
        } else {
            processedImage = image
        }
        
        material.diffuse.contents = processedImage
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, 1, 1)  // 水平翻转纹理
        material.diffuse.wrapS = .repeat  // 水平重复
        material.diffuse.wrapT = .clamp   // 垂直不重复
        material.isDoubleSided = true     // 允许从内部看到纹理
        
        // 配置材质渲染模式
        material.lightingModel = .constant // 禁用光照以避免阴影
        material.diffuse.magnificationFilter = .linear  // 使用线性过滤提高图像质量
        material.diffuse.minificationFilter = .linear
        material.diffuse.mipFilter = .linear
        
        sphere.materials = [material]
        
        let sphereNode = SCNNode(geometry: sphere)
        // 旋转球体以确保正确的初始方向
        sphereNode.rotation = SCNVector4(0, 1, 0, Float.pi)
        scene.rootNode.addChildNode(sphereNode)
        
        // 配置场景视图
        sceneView.scene = scene
        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling4X  // 启用抗锯齿
        
        // 禁用默认的相机控制
        sceneView.allowsCameraControl = false
        
        // 配置手势
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        sceneView.addGestureRecognizer(panGesture)
        
        // 添加捏合手势
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        sceneView.addGestureRecognizer(pinchGesture)
        
        // 保存初始相机方向和引用
        context.coordinator.initialCameraOrientation = cameraNode.orientation
        context.coordinator.cameraNode = cameraNode
        
        return sceneView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {}
    
    // 添加协调器来处理手势
    class Coordinator: NSObject {
        private var previousX: Float = 0
        private var previousY: Float = 0
        private var currentRotationX: Float = 0
        private var currentRotationY: Float = 0
        var initialCameraOrientation = SCNQuaternion(0, 0, 0, 1)
        weak var cameraNode: SCNNode?
        
        // 角度限制
        private let maxVerticalAngle: Float = .pi / 2  // 90度
        private let minVerticalAngle: Float = -.pi / 2 // -90度
        
        // 添加缩放相关属性
        private var initialFOV: CGFloat = 80
        private let minFOV: CGFloat = 30
        private let maxFOV: CGFloat = 120
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let cameraNode = cameraNode else { return }
            
            let translation = gesture.translation(in: gesture.view)
            
            switch gesture.state {
            case .began:
                previousX = 0
                previousY = 0
            case .changed:
                let currentX = Float(translation.x)
                let currentY = Float(translation.y)
                
                let deltaX = currentX - previousX
                let deltaY = currentY - previousY
                
                let sensitivity: Float = 0.005
                
                // 更新当前旋转角度
                currentRotationX += deltaX * sensitivity
                currentRotationY += deltaY * sensitivity
                
                // 限制垂直旋转角度
                currentRotationY = min(max(currentRotationY, minVerticalAngle), maxVerticalAngle)
                
                // 先应用垂直旋转，再应用水平旋转
                var transform = SCNMatrix4Identity
                transform = SCNMatrix4Rotate(transform, currentRotationX, 0, 1, 0)  // 水平旋转
                transform = SCNMatrix4Rotate(transform, currentRotationY, 1, 0, 0)  // 垂直旋转（移除负号）
                
                // 应用旋转
                cameraNode.transform = transform
                
                previousX = currentX
                previousY = currentY
            case .ended:
                // 保存最终角度
                break
            default:
                break
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let camera = cameraNode?.camera else { return }
            
            switch gesture.state {
            case .began:
                initialFOV = camera.fieldOfView
            case .changed:
                // 计算新的FOV，缩放比例与FOV成反比
                var newFOV = initialFOV / gesture.scale
                
                // 限制FOV范围
                newFOV = min(max(newFOV, minFOV), maxFOV)
                
                // 应用新的FOV
                camera.fieldOfView = newFOV
                
            case .ended, .cancelled:
                // 保存最终的FOV作为下次缩放的初始值
                initialFOV = camera.fieldOfView
            default:
                break
            }
        }
    }
}

// 扩展SCNQuaternion以支持四元数乘法
extension SCNQuaternion {
    static func multiply(_ q1: SCNQuaternion, _ q2: SCNQuaternion) -> SCNQuaternion {
        let x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y
        let y = q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x
        let z = q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w
        let w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z
        return SCNQuaternion(x, y, z, w)
    }
}

// MARK: - PanoramaVideoView
struct PanoramaVideoView: UIViewRepresentable {
    let videoURL: URL
    @Binding var isPlaying: Bool
    @Binding var isMuted: Bool
    @Binding var progress: Double
    
    // 改为 internal 访问级别，并使用 weak 引用
    static weak var activeCoordinator: Coordinator?
    private static var activeAudioSession: Bool = false
    
    static func deactivateAudioSession() {
        if activeAudioSession {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                activeAudioSession = false
            } catch {
                print("Failed to deactivate audio session: \(error)")
            }
        }
        // 清理 coordinator
        activeCoordinator?.cleanup()
        activeCoordinator = nil
    }
    
    static func activateAudioSession() {
        if !activeAudioSession {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                activeAudioSession = true
            } catch {
                print("Failed to set audio session category: \(error)")
            }
        }
    }
    
    func makeUIView(context: Context) -> SCNView {
        print("📱 Making new SCNView")
        let sceneView = SCNView()
        
        // 创建并保存新的 coordinator
        let newCoordinator = context.coordinator
        
        // 如果存在旧的 coordinator，先清理
        if Self.activeCoordinator !== newCoordinator {
            Self.activeCoordinator?.cleanup()
            Self.activeCoordinator = newCoordinator
            print("🎮 Set new active coordinator: \(String(describing: newCoordinator))")
        }
        
        let scene = SCNScene()
        
        // 创建相机节点
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 80  // 设置初始FOV为80度
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 0)
        scene.rootNode.addChildNode(cameraNode)
        
        // 创建球体
        let sphere = SCNSphere(radius: 10)
        sphere.segmentCount = 96
        
        // 设置音频会话
        PanoramaVideoView.activateAudioSession()
        
        // 创建视频播放器和输出
        let asset = AVAsset(url: videoURL)
        let playerItem = AVPlayerItem(asset: asset)
        
        // 创建视频输出
        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        playerItem.add(videoOutput)
        
        let player = AVPlayer(playerItem: playerItem)
        newCoordinator.player = player
        newCoordinator.videoOutput = videoOutput
        
        // 设置初始静音状态
        player.isMuted = isMuted
        
        // 添加进度观察者
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let progressObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player,
                  let coordinator = Self.activeCoordinator else {
                print("⚠️ Observer: Player or coordinator is nil")
                return
            }
            
            // 如果正在拖动或跳转中，不更新进度
            if coordinator.isScrubbing || coordinator.isSeekInProgress {
                print("⏭️ Observer: Skip update")
                return
            }
            
            // 只在播放时更新进度
            if player.rate != 0,
               let duration = player.currentItem?.duration,
               duration.isValid,
               duration.seconds > 0 {
                let currentProgress = time.seconds / duration.seconds
                coordinator.progress = currentProgress
            }
        }
        newCoordinator.progressObserver = progressObserver
        
        // 创建并配置材质
        let material = SCNMaterial()
        
        // 创建一个CALayer作为中间层
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(x: 0, y: 0, width: 4096, height: 2048)
        videoLayer.contentsGravity = .resizeAspectFill
        
        material.diffuse.contents = videoLayer
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, 1, 1)
        material.isDoubleSided = true
        material.lightingModel = .constant
        
        // 配置纹理过滤
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        material.diffuse.mipFilter = .linear
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp
        
        sphere.materials = [material]
        
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.rotation = SCNVector4(0, 1, 0, Float.pi)
        scene.rootNode.addChildNode(sphereNode)
        
        // 配置场景视图
        sceneView.scene = scene
        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling4X
        
        // 禁用默认的相机控制
        sceneView.allowsCameraControl = false
        
        // 配置手势
        let panGesture = UIPanGestureRecognizer(target: newCoordinator, action: #selector(Coordinator.handlePan(_:)))
        sceneView.addGestureRecognizer(panGesture)
        
        // 添加捏合手势
        let pinchGesture = UIPinchGestureRecognizer(target: newCoordinator, action: #selector(Coordinator.handlePinch(_:)))
        sceneView.addGestureRecognizer(pinchGesture)
        
        // 保存相机节点引用和视频层
        newCoordinator.cameraNode = cameraNode
        newCoordinator.videoLayer = videoLayer
        
        // 设置视频帧更新
        newCoordinator.setupDisplayLink()
        
        // 添加循环播放观察者
        NotificationCenter.default.addObserver(
            newCoordinator,
            selector: #selector(Coordinator.playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // 开始播放
        if isPlaying {
            player.play()
        }
        
        return sceneView
    }
    
    func updateUIView(_ scnView: SCNView, context: Context) {
        // 更新播放状态
        if let player = context.coordinator.player {
            if isPlaying && player.rate == 0 {
                player.play()
            } else if !isPlaying && player.rate != 0 {
                player.pause()
            }
            player.isMuted = isMuted
        }
    }
    
    func makeCoordinator() -> Coordinator {
        print("🎮 Making new coordinator")
        let coordinator = Coordinator(isPlaying: $isPlaying, isMuted: $isMuted, progress: $progress)
        return coordinator
    }
    
    class Coordinator: NSObject {
        var player: AVPlayer?
        var videoOutput: AVPlayerItemVideoOutput?
        var videoLayer: CALayer?
        var displayLink: CADisplayLink?
        var progressObserver: Any?
        var isScrubbing: Bool = false
        var isSeekInProgress: Bool = false
        @Binding var isPlaying: Bool
        @Binding var isMuted: Bool
        @Binding var progress: Double
        private var previousX: Float = 0
        private var previousY: Float = 0
        private var currentRotationX: Float = 0
        private var currentRotationY: Float = 0
        weak var cameraNode: SCNNode?
        
        private let maxVerticalAngle: Float = .pi / 2
        private let minVerticalAngle: Float = -.pi / 2
        
        // 添加缩放相关属性
        private var initialFOV: CGFloat = 80
        private let minFOV: CGFloat = 30
        private let maxFOV: CGFloat = 120
        
        init(isPlaying: Binding<Bool>, isMuted: Binding<Bool>, progress: Binding<Double>) {
            _isPlaying = isPlaying
            _isMuted = isMuted
            _progress = progress
            super.init()
            print("🎮 Coordinator initialized")
        }
        
        deinit {
            print("🎮 Coordinator deinit")
            cleanup()
        }
        
        func cleanup() {
            print("🎮 Cleanup started")
            // 停止播放器
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            
            // 移除进度观察者
            if let observer = progressObserver {
                player?.removeTimeObserver(observer)
                progressObserver = nil
            }
            
            // 停止显示链接
            displayLink?.invalidate()
            displayLink = nil
            
            // 移除通知观察者
            NotificationCenter.default.removeObserver(self)
            
            // 清理引用
            player = nil
            videoOutput = nil
            videoLayer = nil
            cameraNode = nil
            
            print("🎮 Cleanup completed")
        }
        
        func setupDisplayLink() {
            displayLink = CADisplayLink(target: self, selector: #selector(updateVideoFrame))
            displayLink?.add(to: .main, forMode: .common)
        }
        
        @objc func updateVideoFrame() {
            guard let output = videoOutput,
                  let player = player,
                  let videoLayer = videoLayer else { return }
            
            let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: itemTime) {
                if let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
                    videoLayer.contents = pixelBuffer
                }
            }
        }
        
        @objc func playerDidFinishPlaying() {
            // 循环播放
            player?.seek(to: CMTime.zero)
            player?.play()
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let cameraNode = cameraNode else { return }
            
            let translation = gesture.translation(in: gesture.view)
            
            switch gesture.state {
            case .began:
                previousX = 0
                previousY = 0
            case .changed:
                let currentX = Float(translation.x)
                let currentY = Float(translation.y)
                
                let deltaX = currentX - previousX
                let deltaY = currentY - previousY
                
                let sensitivity: Float = 0.005
                
                // 更新当前旋转角度
                currentRotationX += deltaX * sensitivity
                currentRotationY += deltaY * sensitivity
                
                // 限制垂直旋转角度
                currentRotationY = min(max(currentRotationY, minVerticalAngle), maxVerticalAngle)
                
                // 先应用垂直旋转，再应用水平旋转
                var transform = SCNMatrix4Identity
                transform = SCNMatrix4Rotate(transform, currentRotationX, 0, 1, 0)  // 水平旋转
                transform = SCNMatrix4Rotate(transform, currentRotationY, 1, 0, 0)  // 垂直旋转
                
                // 应用旋转
                cameraNode.transform = transform
                
                previousX = currentX
                previousY = currentY
            case .ended:
                break
            default:
                break
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let camera = cameraNode?.camera else { return }
            
            switch gesture.state {
            case .began:
                initialFOV = camera.fieldOfView
            case .changed:
                // 计算新的FOV，缩放比例与FOV成反比
                var newFOV = initialFOV / gesture.scale
                
                // 限制FOV范围
                newFOV = min(max(newFOV, minFOV), maxFOV)
                
                // 应用新的FOV
                camera.fieldOfView = newFOV
                
            case .ended, .cancelled:
                // 保存最终的FOV作为下次缩放的初始值
                initialFOV = camera.fieldOfView
            default:
                break
            }
        }
        
        // 添加进度控制方法
        func seek(to targetProgress: Double) {
            guard let player = player,
                  let duration = player.currentItem?.duration,
                  duration.isValid,
                  duration.seconds > 0,
                  !isSeekInProgress else {
                print("⚠️ Seek: Invalid state")
                print("  - isSeekInProgress: \(isSeekInProgress)")
                print("  - player: \(String(describing: player))")
                return
            }
            
            print("🎯 Seek: Starting")
            print("  - Target progress: \(targetProgress)")
            
            // 标记seek开始
            isSeekInProgress = true
            
            // 记录当前是否正在播放
            let wasPlaying = isPlaying
            
            // 暂停播放和进度更新
            player.pause()
            
            let time = CMTime(seconds: duration.seconds * targetProgress, preferredTimescale: duration.timescale)
            
            // 使用精确跳转
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if finished {
                        // 更新进度状态
                        self.progress = targetProgress
                        
                        // 如果之前是播放状态，恢复播放
                        if wasPlaying {
                            self.isPlaying = true
                            player.play()
                        }
                        
                        // 重置状态标记
                        self.isSeekInProgress = false
                        self.isScrubbing = false
                    } else {
                        // seek失败时也要重置状态
                        self.isSeekInProgress = false
                        self.isScrubbing = false
                    }
                }
            }
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @EnvironmentObject var mediaManager: PanoramaMediaManager
    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?
    @State private var isImagePickerPresented = false
    @State private var isFilePickerPresented = false
    @State private var isPlaying = false  // 初始状态设为 false
    @State private var mediaType: MediaType = .image
    @State private var showControls = false
    @State private var orientation = UIDevice.current.orientation
    @State private var showingOptions = false
    @State private var videoCoordinator: PanoramaVideoView.Coordinator?
    @State private var isMuted = false
    @State private var videoProgress: Double = 0
    @State private var isSharePresented = false // 新增：分享面板状态
    
    // 多选相关状态
    @State private var isSelectMode = false
    @State private var selectedMediaItems: Set<UUID> = []
    @State private var isMultiSharePresented = false
    @State private var shareableItems: [Any] = []
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    private var columns: [GridItem] {
        let minWidth: CGFloat = verticalSizeClass == .regular ? 160 : 200
        return [
            GridItem(.adaptive(minimum: minWidth), spacing: 16)
        ]
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = selectedImage, mediaType == .image {
                    PanoramaView(image: image)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                showControls.toggle()
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    if showControls {
                        mediaControls
                    }
                } else if let videoURL = selectedVideoURL, mediaType == .video {
                    PanoramaVideoView(videoURL: videoURL, 
                                    isPlaying: $isPlaying, 
                                    isMuted: $isMuted,
                                    progress: $videoProgress)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                showControls.toggle()
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id(videoURL)  // 确保 URL 变化时重新创建视图
                        .onAppear {
                            print("🎥 Video view appeared")
                            // 延迟一下再开始播放
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isPlaying = true
                            }
                        }
                        .onDisappear {
                            print("🎥 Video view disappeared")
                            isPlaying = false
                            if mediaType == .video {
                                PanoramaVideoView.deactivateAudioSession()
                            }
                        }
                    if showControls {
                        mediaControls
                    }
                } else {
                    NavigationView {
                        Group {
                            switch mediaManager.authorizationStatus {
                            case .notDetermined, .restricted, .denied:
                                VStack(spacing: 20) {
                                    Image(systemName: "photo.circle")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 100, height: 100)
                                        .foregroundColor(.gray)
                                    
                                    Text("need_photo_access".localized())
                                        .font(.headline)
                                    
                                    Text("allow_access_description".localized())
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                    
                                    Button(action: {
                                        if let url = URL(string: UIApplication.openSettingsURLString) {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Text("go_to_settings".localized())
                                            .foregroundColor(.white)
                                            .padding()
                                            .background(Color.blue)
                                            .cornerRadius(10)
                                    }
                                }
                            case .authorized, .limited:
                                ScrollView {
                                    LazyVGrid(columns: columns, spacing: verticalSizeClass == .regular ? 16 : 12) {
                                        ForEach(mediaManager.panoramaMedia) { media in
                                            MediaThumbnailView(
                                                media: media,
                                                onTap: { media in
                                                    loadAndDisplayMedia(media)
                                                },
                                                isSelectMode: isSelectMode,
                                                isSelected: selectedMediaItems.contains(media.id),
                                                onToggleSelection: { id in
                                                    toggleSelection(id)
                                                }
                                            )
                                        }
                                    }
                                    .padding(verticalSizeClass == .regular ? 16 : 12)
                                }
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .navigationTitle("panorama_media_library".localized())
                        .navigationBarTitleDisplayMode(verticalSizeClass == .regular ? .large : .inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                if isSelectMode {
                                    Button(action: {
                                        isSelectMode = false
                                        selectedMediaItems.removeAll()
                                    }) {
                                        Text("cancel".localized())
                                    }
                                } else {
                                    Button(action: {
                                        showingOptions = true
                                    }) {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.title2)
                                    }
                                }
                            }
                            
                            ToolbarItem(placement: .navigationBarLeading) {
                                if !isSelectMode && !mediaManager.panoramaMedia.isEmpty {
                                    Button(action: {
                                        isSelectMode = true
                                    }) {
                                        Text("select".localized())
                                    }
                                }
                            }
                        }
                        
                        // 添加多选模式下的底部工具栏
                        .overlay(
                            Group {
                                if isSelectMode && !selectedMediaItems.isEmpty {
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            
                                            Button(action: {
                                                prepareSelectedItemsForSharing()
                                            }) {
                                                VStack {
                                                    Image(systemName: "square.and.arrow.up")
                                                        .font(.title2)
                                                    Text("share".localized())
                                                        .font(.caption)
                                                }
                                                .foregroundColor(.white)
                                                .padding()
                                            }
                                            
                                            Spacer()
                                        }
                                        .background(Color.black.opacity(0.7))
                                    }
                                }
                            }
                        )
                        
                        // 添加空图作为详情视图，防止分栏显示
                        EmptyView()
                    }
                    .navigationViewStyle(StackNavigationViewStyle()) // 强制使用堆栈样式
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .sheet(isPresented: $isImagePickerPresented) {
            ImagePicker(image: $selectedImage, videoURL: $selectedVideoURL, mediaType: $mediaType)
        }
        .sheet(isPresented: $isFilePickerPresented) {
            UnifiedFilePicker(image: $selectedImage, videoURL: $selectedVideoURL, mediaType: $mediaType)
        }
        .sheet(isPresented: $isMultiSharePresented) {
            // 批量分享视图
            ShareViewController(items: shareableItems, activities: nil)
                .onDisappear {
                    // 分享完成后退出选择模式
                    if isSelectMode {
                        isSelectMode = false
                        selectedMediaItems.removeAll()
                    }
                }
        }
        .actionSheet(isPresented: $showingOptions) {
            ActionSheet(
                title: Text("select_media".localized()),
                buttons: [
                    .default(Text("from_photos".localized())) {
                        isImagePickerPresented = true
                    },
                    .default(Text("from_files".localized())) {
                        isFilePickerPresented = true
                    },
                    .cancel(Text("cancel".localized()))
                ]
            )
        }
        .onChange(of: selectedVideoURL) { _ in
            // 重置播放状态
            isPlaying = true
        }
        // 添加分享面板
        .sheet(isPresented: $isSharePresented) {
            if mediaType == .image {
                // 显示加载指示器
                LoadingView(message: "preparing_media".localized())
            } else if let videoURL = selectedVideoURL, mediaType == .video {
                ShareViewController(items: [videoURL], activities: nil)
            }
        }
    }
    
    private func loadAndDisplayMedia(_ media: PanoramaMedia) {
        // 如果当前正在播放视频，先清理
        if mediaType == .video {
            PanoramaVideoView.deactivateAudioSession()
        }
        
        switch media.type {
        case .image:
            mediaManager.loadFullResolutionImage(for: media.asset) { url in
                if let url = url,
                   let image = UIImage(contentsOfFile: url.path) {
                    DispatchQueue.main.async {
                        self.selectedVideoURL = nil  // 清除视频URL
                        self.selectedImage = image
                        self.mediaType = .image
                    }
                }
            }
        case .video:
            mediaManager.loadVideo(for: media.asset) { url in
                if let url = url {
                    DispatchQueue.main.async {
                        self.selectedImage = nil  // 清除图片
                        self.selectedVideoURL = url
                        self.mediaType = .video
                        self.isPlaying = true
                    }
                }
            }
        }
    }
    
    private var mediaControls: some View {
        VStack {
            // 顶部控制按钮
            HStack {
                Button(action: {
                    // 如果当前是视频，先清理音频会话和播放器
                    if mediaType == .video {
                        videoCoordinator?.cleanup()
                        videoCoordinator = nil
                        PanoramaVideoView.deactivateAudioSession()
                    }
                    
                    // 重置所有状态
                    selectedImage = nil
                    selectedVideoURL = nil
                    showControls = false
                    isPlaying = false
                    isMuted = false
                    videoProgress = 0
                    mediaType = .image
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                // 添加分享按钮
                Button(action: {
                    // 显示加载指示器
                    let loadingAlert = UIAlertController(
                        title: "preparing_media".localized(),
                        message: "please_wait".localized(),
                        preferredStyle: .alert
                    )
                    
                    let rootVC = UIApplication.shared.windows.first?.rootViewController
                    rootVC?.present(loadingAlert, animated: true)
                    
                    // 延迟一下再关闭加载指示器，以便文件处理完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        loadingAlert.dismiss(animated: true) {
                            isSharePresented = true
                        }
                    }
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
            }
            .padding()
            
            Spacer()
            
            // 底部控制栏
            if mediaType == .video {
                HStack(spacing: 12) {
                    // 播放/暂停按钮
                    Button(action: {
                        isPlaying.toggle()
                    }) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    
                    // 进度条
                    Slider(value: $videoProgress, in: 0...1, onEditingChanged: { editing in
                        guard let coordinator = PanoramaVideoView.activeCoordinator else {
                            print("⚠️ Slider: coordinator is nil")
                            return
                        }
                        
                        if editing {
                            // 开始拖动时暂停播放和进度更新
                            coordinator.isScrubbing = true
                            coordinator.player?.pause()
                        } else {
                            // 拖动结束后跳转到新位置，并保持原来的播放状态
                            coordinator.seek(to: videoProgress)
                        }
                    })
                    .accentColor(.white)
                    
                    // 静音按钮
                    Button(action: {
                        isMuted.toggle()
                        videoCoordinator?.player?.isMuted = isMuted
                    }) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.5))
            }
        }
        .transition(.opacity)
        .onAppear {
            // 5秒后自动隐藏控制栏
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation {
                    if showControls {
                        showControls = false
                    }
                }
            }
        }
    }
    
    private func prepareSelectedItemsForSharing() {
        guard !selectedMediaItems.isEmpty else { return }
        
        // 清空之前的分享项
        shareableItems.removeAll()
        
        // 显示加载指示器
        let loadingAlert = UIAlertController(
            title: "preparing_media".localized(),
            message: "please_wait".localized(),
            preferredStyle: .alert
        )
        
        let rootVC = UIApplication.shared.windows.first?.rootViewController
        rootVC?.present(loadingAlert, animated: true)
        
        // 创建一个计数器来跟踪加载的媒体数量
        let totalItems = selectedMediaItems.count
        var loadedItems = 0
        
        // 获取选中的媒体项
        let selectedMedia = mediaManager.panoramaMedia.filter { selectedMediaItems.contains($0.id) }
        
        // 处理分享项目完成后的回调
        let finishLoading = {
            // 关闭加载指示器
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    // 只有在有内容可分享时才显示分享面板
                    if !self.shareableItems.isEmpty {
                        self.isMultiSharePresented = true
                    }
                }
            }
        }
        
        // 为每个选中的媒体项加载完整内容
        for media in selectedMedia {
            switch media.type {
            case .image:
                mediaManager.loadFullResolutionImage(for: media.asset) { url in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.shareableItems.append(url)
                            loadedItems += 1
                            
                            // 所有项目加载完毕时，显示分享面板
                            if loadedItems == totalItems {
                                finishLoading()
                            }
                        }
                    } else {
                        // 处理加载失败的情况
                        loadedItems += 1
                        if loadedItems == totalItems {
                            finishLoading()
                        }
                    }
                }
                
            case .video:
                mediaManager.loadVideo(for: media.asset) { url in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.shareableItems.append(url)
                            loadedItems += 1
                            
                            // 所有项目加载完毕时，显示分享面板
                            if loadedItems == totalItems {
                                finishLoading()
                            }
                        }
                    } else {
                        // 处理加载失败的情况
                        loadedItems += 1
                        if loadedItems == totalItems {
                            finishLoading()
                        }
                    }
                }
            }
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        if isSelectMode {
            if selectedMediaItems.contains(id) {
                selectedMediaItems.remove(id)
            } else {
                selectedMediaItems.insert(id)
            }
        }
    }
}

struct MediaThumbnailView: View {
    let media: PanoramaMedia
    let onTap: (PanoramaMedia) -> Void
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var showingOptions = false
    @EnvironmentObject var mediaManager: PanoramaMediaManager
    @State private var isSharePresented = false
    @State private var shareableItem: Any? = nil
    
    // 多选模式相关属性
    var isSelectMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: ((UUID) -> Void)? = nil
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Button(action: {
                    if isSelectMode {
                        onToggleSelection?(media.id)
                    } else {
                        onTap(media)
                    }
                }) {
                    ZStack {
                        if let thumbnail = media.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(2/1, contentMode: .fill)
                                .frame(height: verticalSizeClass == .regular ? 100 : 80)
                                .clipped()
                                .cornerRadius(8)
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .aspectRatio(2/1, contentMode: .fill)
                                .frame(height: verticalSizeClass == .regular ? 100 : 80)
                                .cornerRadius(8)
                        }
                        
                        if media.type == .video {
                            Image(systemName: "play.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: verticalSizeClass == .regular ? 100 : 80)
                }
                
                // 多选指示器
                if isSelectMode {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundColor(isSelected ? .blue : .white)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .contextMenu {
                if !isSelectMode {
                    Button(action: {
                        prepareForSharing()
                    }) {
                        Label("share".localized(), systemImage: "square.and.arrow.up")
                    }
                }
            }
            .onLongPressGesture {
                if !isSelectMode {
                    showingOptions = true
                }
            }
        }
        .frame(height: verticalSizeClass == .regular ? 100 : 80)
        .actionSheet(isPresented: $showingOptions) {
            ActionSheet(
                title: Text("select_action".localized()),
                buttons: [
                    .default(Text("share".localized())) {
                        prepareForSharing()
                    },
                    .cancel()
                ]
            )
        }
        .sheet(isPresented: $isSharePresented) {
            if let item = shareableItem {
                ShareViewController(items: [item], activities: nil)
            }
        }
    }
    
    private func prepareForSharing() {
        // 显示加载指示器
        let loadingAlert = UIAlertController(
            title: "preparing_media".localized(),
            message: "please_wait".localized(),
            preferredStyle: .alert
        )
        
        let rootVC = UIApplication.shared.windows.first?.rootViewController
        rootVC?.present(loadingAlert, animated: true)
        
        switch media.type {
        case .image:
            mediaManager.loadFullResolutionImage(for: media.asset) { url in
                if let url = url {
                    DispatchQueue.main.async {
                        loadingAlert.dismiss(animated: true) {
                            self.shareableItem = url
                            self.isSharePresented = true
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        loadingAlert.dismiss(animated: true)
                    }
                }
            }
        case .video:
            mediaManager.loadVideo(for: media.asset) { url in
                if let url = url {
                    DispatchQueue.main.async {
                        loadingAlert.dismiss(animated: true) {
                            self.shareableItem = url
                            self.isSharePresented = true
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        loadingAlert.dismiss(animated: true)
                    }
                }
            }
        }
    }
}

// MARK: - ImagePicker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var videoURL: URL?
    @Binding var mediaType: MediaType
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            
            guard let result = results.first else { return }
            
            // 处理图片
            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                    if let image = image as? UIImage {
                        DispatchQueue.main.async {
                            // 如果之前在播放视频，先清理音频会话
                            if self.parent.videoURL != nil {
                                PanoramaVideoView.deactivateAudioSession()
                            }
                            self.parent.videoURL = nil  // 清除视频URL
                            self.parent.image = image
                            self.parent.mediaType = .image
                        }
                    }
                }
            }
            // 处理视频
            else if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                // 先清理现有的视频资源
                if self.parent.videoURL != nil {
                    PanoramaVideoView.deactivateAudioSession()
                }
                
                // 使用 assetIdentifier 获取 PHAsset
                if let identifier = result.assetIdentifier,
                   let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject {
                    // 使用 PHImageManager 获取视频 URL
                    let options = PHVideoRequestOptions()
                    options.version = .current
                    options.deliveryMode = .highQualityFormat
                    options.isNetworkAccessAllowed = true  // 允许从 iCloud 下载
                    
                    PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                        guard let urlAsset = avAsset as? AVURLAsset else { 
                            print("❌ Failed to get URL asset")
                            return 
                        }
                        
                        // 创建本地副本
                        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let uniqueFileName = UUID().uuidString + ".mov"
                        let localURL = documentsDirectory.appendingPathComponent(uniqueFileName)
                        
                        do {
                            if FileManager.default.fileExists(atPath: localURL.path) {
                                try FileManager.default.removeItem(at: localURL)
                            }
                            try FileManager.default.copyItem(at: urlAsset.url, to: localURL)
                            
                            DispatchQueue.main.async {
                                print("🎥 Video loaded successfully")
                                self.parent.image = nil  // 清除图片
                                self.parent.videoURL = localURL
                                self.parent.mediaType = .video  // 设置媒体类型为视频
                            }
                        } catch {
                            print("❌ Error copying video file: \(error)")
                        }
                    }
                } else {
                    print("⚠️ Fallback to direct file loading")
                    // 如果无法获取 assetIdentifier，回退到直接加载文件
                    result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                        guard let url = url else { 
                            print("❌ Failed to get URL from file representation")
                            return 
                        }
                        
                        // 创建本地副本
                        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let uniqueFileName = UUID().uuidString + "." + url.pathExtension
                        let localURL = documentsDirectory.appendingPathComponent(uniqueFileName)
                        
                        do {
                            if FileManager.default.fileExists(atPath: localURL.path) {
                                try FileManager.default.removeItem(at: localURL)
                            }
                            try FileManager.default.copyItem(at: url, to: localURL)
                            
                            DispatchQueue.main.async {
                                print("🎥 Video loaded successfully (fallback)")
                                self.parent.image = nil  // 清除图片
                                self.parent.videoURL = localURL
                                self.parent.mediaType = .video  // 设置媒体类型为视频
                            }
                        } catch {
                            print("❌ Error copying video file: \(error)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - UnifiedFilePicker
struct UnifiedFilePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var videoURL: URL?
    @Binding var mediaType: MediaType
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [.image, .movie, .video]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: UnifiedFilePicker
        
        init(_ parent: UnifiedFilePicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let uniqueFileName = UUID().uuidString + "." + url.pathExtension
            let localURL = documentsDirectory.appendingPathComponent(uniqueFileName)
            
            do {
                if FileManager.default.fileExists(atPath: localURL.path) {
                    try FileManager.default.removeItem(at: localURL)
                }
                try FileManager.default.copyItem(at: url, to: localURL)
                
                if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
                    if let image = UIImage(contentsOfFile: localURL.path) {
                        DispatchQueue.main.async {
                            // 如果之前在播放视频，先清理音频会话
                            if self.parent.mediaType == .video {
                                PanoramaVideoView.deactivateAudioSession()
                            }
                            self.parent.videoURL = nil  // 清除视频URL
                            self.parent.mediaType = .image
                            self.parent.image = image
                            self.parent.presentationMode.wrappedValue.dismiss()
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        // 如果之前在播放视频，先清理音频会话
                        if self.parent.mediaType == .video {
                            PanoramaVideoView.deactivateAudioSession()
                        }
                        self.parent.image = nil  // 清除图片
                        self.parent.mediaType = .video
                        self.parent.videoURL = localURL
                        self.parent.presentationMode.wrappedValue.dismiss()
                    }
                }
            } catch {
                print("Error copying file: \(error)")
            }
        }
    }
}

// MARK: - ShareViewController
struct ShareViewController: UIViewControllerRepresentable {
    let items: [Any]
    let activities: [UIActivity]?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        print("📤 Starting share process with \(items.count) items")
        
        // 转换共享项目
        let activityItems = items.map { item -> Any in
            if let url = item as? URL, url.isFileURL {
                print("📤 Processing file URL for sharing: \(url.lastPathComponent)")
                // 创建临时文件副本
                let tempURL = createTempCopy(of: url)
                return FileActivityItemSource(url: tempURL ?? url, coordinatorQueue: &context.coordinator.trackingURLs)
            } else if let image = item as? UIImage {
                print("📤 Processing image for sharing")
                return image
            } else {
                print("📤 Unknown item type: \(type(of: item))")
                return item
            }
        }
        
        // 创建分享控制器
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: activities
        )
        
        // 监听分享完成事件
        controller.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            print("📤 Share completion handler called")
            print("  - Activity type: \(String(describing: activityType?.rawValue))")
            print("  - Completed: \(completed)")
            
            if let error = error {
                print("❌ Share error: \(error.localizedDescription)")
            }
            
            // 延迟释放资源，确保AirDrop完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                context.coordinator.cleanupAll()
                self.presentationMode.wrappedValue.dismiss()
            }
        }
        
        return controller
    }
    
    // 创建临时文件副本
    private func createTempCopy(of url: URL) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)
        
        do {
            // 如果已存在，先删除
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            
            // 复制文件
            try FileManager.default.copyItem(at: url, to: tempURL)
            
            // 设置文件权限
            try FileManager.default.setAttributes([
                .posixPermissions: 0o644
            ], ofItemAtPath: tempURL.path)
            
            print("📁 Created temporary copy at: \(tempURL.path)")
            return tempURL
        } catch {
            print("❌ Failed to create temporary copy: \(error)")
            return nil
        }
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    class Coordinator: NSObject {
        var trackingURLs: [URLAccess] = []
        var tempFiles: [URL] = []
        
        func cleanupAll() {
            print("🧹 Cleaning up resources")
            
            // 清理临时文件
            for url in tempFiles {
                do {
                    try FileManager.default.removeItem(at: url)
                    print("  - Removed temp file: \(url.lastPathComponent)")
                } catch {
                    print("  - Failed to remove temp file: \(error)")
                }
            }
            tempFiles.removeAll()
            
            // 停止访问权限
            for access in trackingURLs {
                access.stopAccess()
            }
            print("  - Released \(trackingURLs.count) security-scoped URLs")
            trackingURLs.removeAll()
        }
        
        deinit {
            print("🧹 Coordinator deinit")
            cleanupAll()
        }
    }
}

// 用于追踪URL访问权限的辅助类
class URLAccess {
    let url: URL
    private(set) var isAccessing: Bool = false
    private var accessStartTime: Date?
    
    init(url: URL) {
        self.url = url
        print("🔒 Created URLAccess for: \(url.lastPathComponent)")
    }
    
    func startAccess() -> Bool {
        // 如果已经在访问中，先停止之前的访问
        if isAccessing {
            stopAccess()
        }
        
        // 尝试获取新的访问权限
        isAccessing = url.startAccessingSecurityScopedResource()
        if isAccessing {
            accessStartTime = Date()
            print("🔐 Started accessing: \(url.lastPathComponent)")
            print("  - Access time: \(accessStartTime?.description ?? "unknown")")
        } else {
            print("❌ Failed to start accessing: \(url.lastPathComponent)")
        }
        return isAccessing
    }
    
    func stopAccess() {
        guard isAccessing else { return }
        url.stopAccessingSecurityScopedResource()
        let duration = accessStartTime.map { Date().timeIntervalSince($0) } ?? 0
        print("🔓 Stopped accessing: \(url.lastPathComponent)")
        print("  - Access duration: \(String(format: "%.2f", duration))s")
        isAccessing = false
        accessStartTime = nil
    }
    
    deinit {
        if isAccessing {
            stopAccess()
        }
    }
}

// 使用NSObject而不是UIActivityItemProvider，以更好地控制文件访问
class FileActivityItemSource: NSObject, UIActivityItemSource {
    private let url: URL
    private var hasStartedSharing: Bool = false
    private var activityType: UIActivity.ActivityType?
    private var lastAccessTime: Date?
    private var accessCount: Int = 0
    
    init(url: URL, coordinatorQueue: inout [URLAccess]) {
        self.url = url
        super.init()
        
        print("\n📤 [FileActivityItemSource] Initializing for file: \(url.lastPathComponent)")
        print("  - File path: \(url.path)")
        print("  - Is file URL: \(url.isFileURL)")
        
        // 验证文件状态
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            print("\n📄 File Status:")
            print("  - Exists: \(FileManager.default.fileExists(atPath: url.path))")
            print("  - Is readable: \(FileManager.default.isReadableFile(atPath: url.path))")
            print("  - Size: \(ByteCountFormatter.string(fromByteCount: Int64(attributes[.size] as? UInt64 ?? 0), countStyle: .file))")
            print("  - Creation date: \(attributes[.creationDate] as? Date ?? Date())")
            print("  - Permissions: \(String(format: "%o", attributes[.posixPermissions] as? Int ?? 0))")
            print("  - Owner: \(attributes[.ownerAccountName] as? String ?? "unknown")")
        } catch {
            print("❌ File verification error: \(error.localizedDescription)")
        }
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        print("\n📋 [Placeholder] Requested for: \(url.lastPathComponent)")
        return url.lastPathComponent
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        print("\n📤 [ItemForActivity] Type: \(String(describing: activityType?.rawValue))")
        print("  - File: \(url.lastPathComponent)")
        
        self.activityType = activityType
        
        // 验证文件状态
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        let isReadable = FileManager.default.isReadableFile(atPath: url.path)
        
        print("  - File exists: \(fileExists)")
        print("  - Is readable: \(isReadable)")
        
        if !fileExists || !isReadable {
            print("❌ File is not accessible")
            return nil
        }
        
        hasStartedSharing = true
        return url
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        print("\n🏷 [DataTypeIdentifier] Requested")
        print("  - Activity type: \(String(describing: activityType?.rawValue))")
        print("  - File extension: \(url.pathExtension.lowercased())")
        
        let typeIdentifier: String
        switch url.pathExtension.lowercased() {
        case "mov":
            typeIdentifier = "com.apple.quicktime-movie"
        case "mp4":
            typeIdentifier = "public.mpeg-4"
        case "jpg", "jpeg":
            typeIdentifier = "public.jpeg"
        case "png":
            typeIdentifier = "public.png"
        default:
            typeIdentifier = "public.data"
        }
        
        print("  - Selected type identifier: \(typeIdentifier)")
        return typeIdentifier
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, 
                              thumbnailImageForActivityType activityType: UIActivity.ActivityType?, 
                              suggestedSize size: CGSize) -> UIImage? {
        print("\n🖼 [Thumbnail] Requested")
        print("  - Activity type: \(String(describing: activityType?.rawValue))")
        print("  - Suggested size: \(size)")
        
        // 为视频生成缩略图
        if url.pathExtension.lowercased() == "mov" || url.pathExtension.lowercased() == "mp4" {
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: CMTime.zero, actualTime: nil)
                print("  - Thumbnail generated successfully")
                return UIImage(cgImage: cgImage)
            } catch {
                print("❌ Thumbnail generation failed: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, 
                              subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        let subject = url.deletingPathExtension().lastPathComponent
        print("\n📝 [Subject] Requested: \(subject)")
        return subject
    }
    
    deinit {
        print("\n🧹 [FileActivityItemSource] Deinit")
        print("  - File: \(url.lastPathComponent)")
        print("  - Total access count: \(accessCount)")
        print("  - Last access time: \(String(describing: lastAccessTime))")
        print("  - Activity type: \(String(describing: activityType?.rawValue))")
        print("  - Has started sharing: \(hasStartedSharing)")
    }
}

struct LoadingView: View {
    let message: String
    
    var body: some View {
        VStack {
            ProgressView()
                .padding()
            Text(message)
        }
    }
}

// MARK: - Previews
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
