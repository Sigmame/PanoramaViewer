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
import Photos

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
                                            MediaThumbnailView(media: media) { media in
                                                loadAndDisplayMedia(media)
                                            }
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
                                Button(action: {
                                    showingOptions = true
                                }) {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title2)
                                }
                            }
                        }
                        
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
    }
    
    private func loadAndDisplayMedia(_ media: PanoramaMedia) {
        // 如果当前正在播放视频，先清理
        if mediaType == .video {
            PanoramaVideoView.deactivateAudioSession()
        }
        
        switch media.type {
        case .image:
            mediaManager.loadFullResolutionImage(for: media.asset) { image in
                if let image = image {
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
            HStack {
                // 返回按钮
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
                
                // 分享按钮 - 修改分享逻辑
                Button(action: {
                    if mediaType == .image {
                        // 找到当前正在查看的资源
                        if let currentMedia = mediaManager.panoramaMedia.first(where: { $0.type == .image }) {
                            mediaManager.prepareForSharing(asset: currentMedia.asset) { items, error in
                                if let error = error {
                                    print("Error preparing for sharing: \(error)")
                                    return
                                }
                                
                                DispatchQueue.main.async {
                                    let activityVC = UIActivityViewController(
                                        activityItems: items,
                                        applicationActivities: nil
                                    )
                                    
                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let window = windowScene.windows.first,
                                       let rootVC = window.rootViewController {
                                        if let popover = activityVC.popoverPresentationController {
                                            popover.sourceView = rootVC.view
                                            popover.sourceRect = CGRect(x: UIScreen.main.bounds.width - 64, y: 64, width: 0, height: 0)
                                            popover.permittedArrowDirections = [.up, .down]
                                        }
                                        rootVC.present(activityVC, animated: true)
                                    }
                                }
                            }
                        }
                    } else if mediaType == .video, let videoURL = selectedVideoURL {
                        let activityVC = UIActivityViewController(
                            activityItems: [videoURL],
                            applicationActivities: nil
                        )
                        
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first,
                           let rootVC = window.rootViewController {
                            if let popover = activityVC.popoverPresentationController {
                                popover.sourceView = rootVC.view
                                popover.sourceRect = CGRect(x: UIScreen.main.bounds.width - 64, y: 64, width: 0, height: 0)
                                popover.permittedArrowDirections = [.up, .down]
                            }
                            rootVC.present(activityVC, animated: true)
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
                .padding(.trailing)
            }
            .padding(.horizontal)
            .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)

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
}

// 在 MediaThumbnailView 之前添加 ActivityViewController 的定义
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct MediaThumbnailView: View {
    let media: PanoramaMedia
    let onTap: (PanoramaMedia) -> Void
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var isShowingShareSheet = false
    @State private var shareItems: [Any] = []
    @EnvironmentObject var mediaManager: PanoramaMediaManager
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Button(action: {
                    onTap(media)
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
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            mediaManager.prepareForSharing(asset: media.asset) { items, error in
                                if let error = error {
                                    print("Error preparing for sharing: \(error)")
                                    return
                                }
                                shareItems = items
                                isShowingShareSheet = true
                            }
                        }
                )
            }
            .sheet(isPresented: $isShowingShareSheet) {
                if !shareItems.isEmpty {
                    ActivityViewController(activityItems: shareItems)
                        .ignoresSafeArea()
                }
            }
        }
        .frame(height: verticalSizeClass == .regular ? 100 : 80)
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

// MARK: - Previews
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
