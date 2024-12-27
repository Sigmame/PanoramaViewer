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
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 0)
        scene.rootNode.addChildNode(cameraNode)
        
        // 创建球体 - 使用更高的细分度以获得更好的渲染效果
        let sphere = SCNSphere(radius: 10)
        sphere.segmentCount = 96  // 增加球体的细分度
        
        // 创建并配置材质
        let material = SCNMaterial()
        material.diffuse.contents = image
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
        
        // 保存初始相机方向
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
        private let maxVerticalAngle: Float = .pi / 3  // 60度
        private let minVerticalAngle: Float = -.pi / 3 // -60度
        
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
                transform = SCNMatrix4Rotate(transform, -currentRotationY, 1, 0, 0) // 垂直旋转（注意负号）
                
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
    @Binding var progress: Double
    
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        let scene = SCNScene()
        
        // 创建相机节点
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 0)
        scene.rootNode.addChildNode(cameraNode)
        
        // 创建球体
        let sphere = SCNSphere(radius: 10)
        sphere.segmentCount = 96
        
        // 创建视频播放器和输出
        let asset = AVAsset(url: videoURL)
        let playerItem = AVPlayerItem(asset: asset)
        
        // 创建视频输出
        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        playerItem.add(videoOutput)
        
        let player = AVPlayer(playerItem: playerItem)
        context.coordinator.player = player
        context.coordinator.videoOutput = videoOutput
        
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
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        sceneView.addGestureRecognizer(panGesture)
        
        // 保存相机节点引用和视频层
        context.coordinator.cameraNode = cameraNode
        context.coordinator.videoLayer = videoLayer
        
        // 设置视频帧更新
        context.coordinator.setupDisplayLink()
        
        // 开始播放
        if isPlaying {
            player.play()
        }
        
        // 添加循环播放观察者
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // 添加进度观察
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        context.coordinator.progressObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let duration = player.currentItem?.duration.seconds ?? 0
            if duration > 0 {
                progress = time.seconds / duration
            }
        }
        
        return sceneView
    }
    
    func updateUIView(_ scnView: SCNView, context: Context) {
        if isPlaying {
            context.coordinator.player?.play()
        } else {
            context.coordinator.player?.pause()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isPlaying: $isPlaying, progress: $progress)
    }
    
    class Coordinator: NSObject {
        var player: AVPlayer?
        var videoOutput: AVPlayerItemVideoOutput?
        var videoLayer: CALayer?
        var displayLink: CADisplayLink?
        var progressObserver: Any?
        @Binding var isPlaying: Bool
        @Binding var progress: Double
        private var previousX: Float = 0
        private var previousY: Float = 0
        private var currentRotationX: Float = 0
        private var currentRotationY: Float = 0
        weak var cameraNode: SCNNode?
        
        // 角度限制
        private let maxVerticalAngle: Float = .pi / 3  // 60度
        private let minVerticalAngle: Float = -.pi / 3 // -60度
        
        init(isPlaying: Binding<Bool>, progress: Binding<Double>) {
            _isPlaying = isPlaying
            _progress = progress
            super.init()
            
            // 添加进度更新通知观察者
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleSeek(_:)),
                name: NSNotification.Name("seekVideo"),
                object: nil
            )
        }
        
        @objc func handleSeek(_ notification: Notification) {
            if let progress = notification.userInfo?["progress"] as? Double {
                seek(to: progress)
            }
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
                transform = SCNMatrix4Rotate(transform, -currentRotationY, 1, 0, 0) // 垂直旋转（注意负号）
                
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
        
        deinit {
            if let observer = progressObserver {
                player?.removeTimeObserver(observer)
            }
            displayLink?.invalidate()
            displayLink = nil
            NotificationCenter.default.removeObserver(self)
            player?.pause()
            player = nil
            videoOutput = nil
            videoLayer = nil
        }
        
        // 添加进度控制方法
        func seek(to progress: Double) {
            guard let player = player,
                  let duration = player.currentItem?.duration else { return }
            
            let time = CMTime(seconds: duration.seconds * progress, preferredTimescale: duration.timescale)
            // 暂停当前播放
            player.pause()
            
            // 使用精确跳转
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                if finished {
                    // 如果之前是播放状态，则恢复播放
                    if self?.isPlaying == true {
                        player.play()
                    }
                }
            }
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?
    @State private var isImagePickerPresented = false
    @State private var isVideoPickerPresented = false
    @State private var isPlaying = true
    @State private var mediaType: MediaType = .image
    @State private var showControls = false
    @State private var videoProgress: Double = 0
    
    enum MediaType {
        case image
        case video
    }
    
    var body: some View {
        ZStack {
            if let image = selectedImage, mediaType == .image {
                PanoramaView(image: image)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            showControls.toggle()
                        }
                    }
                if showControls {
                    mediaControls
                }
            } else if let videoURL = selectedVideoURL, mediaType == .video {
                PanoramaVideoView(videoURL: videoURL, isPlaying: $isPlaying, progress: $videoProgress)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            showControls.toggle()
                        }
                    }
                if showControls {
                    mediaControls
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "photo.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.gray)
                    
                    Button(action: {
                        mediaType = .image
                        isImagePickerPresented = true
                    }) {
                        Text("选择全景图片")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        mediaType = .video
                        isVideoPickerPresented = true
                    }) {
                        Text("选择全景视频")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                }
            }
        }
        .sheet(isPresented: $isImagePickerPresented) {
            ImagePicker(image: $selectedImage)
        }
        .sheet(isPresented: $isVideoPickerPresented) {
            VideoPicker(videoURL: $selectedVideoURL)
        }
    }
    
    private var mediaControls: some View {
        VStack {
            // 顶部返回按钮
            HStack {
                Button(action: {
                    selectedImage = nil
                    selectedVideoURL = nil
                    showControls = false
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                Spacer()
            }
            .padding()
            
            Spacer()
            
            // 底部控制栏
            if mediaType == .video {
                VStack(spacing: 8) {
                    // 进度条和控制按钮在同一行
                    HStack(spacing: 12) {
                        // 播放/暂停按钮
                        Button(action: {
                            isPlaying.toggle()
                        }) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .foregroundColor(.white)
                        }
                        
                        // 视频进度条
                        Slider(value: $videoProgress, in: 0...1, onEditingChanged: { editing in
                            if !editing {
                                // 当用户完成拖动时，发送通知更新视频位置
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("seekVideo"),
                                    object: nil,
                                    userInfo: ["progress": videoProgress]
                                )
                            }
                        })
                        .accentColor(.white)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
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

// MARK: - ImagePicker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
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
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
}

// MARK: - VideoPicker
struct VideoPicker: View {
    @Binding var videoURL: URL?
    @Environment(\.presentationMode) var presentationMode
    @State private var showingSourcePicker = true
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    
    var body: some View {
        Group {
            if showingSourcePicker {
                List {
                    Button(action: {
                        showingSourcePicker = false
                        showingPhotoPicker = true
                    }) {
                        Label("从相册选择", systemImage: "photo.on.rectangle")
                    }
                    
                    Button(action: {
                        showingSourcePicker = false
                        showingFilePicker = true
                    }) {
                        Label("从文件选择", systemImage: "folder")
                    }
                    
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Label("取消", systemImage: "xmark.circle")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoVideoPicker(videoURL: $videoURL, presentationMode: presentationMode)
        }
        .sheet(isPresented: $showingFilePicker) {
            FileVideoPicker(videoURL: $videoURL, presentationMode: presentationMode)
        }
    }
}

// MARK: - PhotoVideoPicker
struct PhotoVideoPicker: UIViewControllerRepresentable {
    @Binding var videoURL: URL?
    var presentationMode: Binding<PresentationMode>
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoVideoPicker
        
        init(_ parent: PhotoVideoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.presentationMode.wrappedValue.dismiss()
                return
            }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    if let error = error {
                        print("Error loading video: \(error)")
                        return
                    }
                    
                    guard let url = url else { return }
                    
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
                            self.parent.videoURL = localURL
                            self.parent.presentationMode.wrappedValue.dismiss()
                        }
                    } catch {
                        print("Error copying video file: \(error)")
                    }
                }
            }
        }
    }
}

// MARK: - FileVideoPicker
struct FileVideoPicker: UIViewControllerRepresentable {
    @Binding var videoURL: URL?
    var presentationMode: Binding<PresentationMode>
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.movie, UTType.video])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FileVideoPicker
        
        init(_ parent: FileVideoPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // 获取对选定URL的安全访问权限
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
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
                    self.parent.videoURL = localURL
                    self.parent.presentationMode.wrappedValue.dismiss()
                }
            } catch {
                print("Error copying video file: \(error)")
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
