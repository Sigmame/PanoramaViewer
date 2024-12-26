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
        
        // 配置相机控制
        sceneView.allowsCameraControl = true
        sceneView.defaultCameraController.maximumVerticalAngle = 85
        sceneView.defaultCameraController.minimumVerticalAngle = -85
        sceneView.defaultCameraController.inertiaEnabled = true  // 启用惯性
        
        // 配置手势
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        sceneView.addGestureRecognizer(panGesture)
        
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
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let sceneView = gesture.view as? SCNView,
                  let cameraNode = sceneView.pointOfView else { return }
            
            let translation = gesture.translation(in: sceneView)
            
            switch gesture.state {
            case .began:
                previousX = 0
                previousY = 0
            case .changed:
                let currentX = Float(translation.x)
                let currentY = Float(translation.y)
                
                let deltaX = currentX - previousX
                let deltaY = currentY - previousY
                
                // 计算相机旋转
                let sensitivity: Float = 0.005  // 降低灵敏度使控制更平滑
                
                // 使用四元数进行旋转，避免万向节锁
                let rotateY = SCNQuaternion(0, 1, 0, -deltaX * sensitivity)
                let rotateX = SCNQuaternion(1, 0, 0, -deltaY * sensitivity)
                
                let currentRotation = cameraNode.orientation
                let yRotation = SCNQuaternion.multiply(currentRotation, rotateY)
                let finalRotation = SCNQuaternion.multiply(yRotation, rotateX)
                
                cameraNode.orientation = finalRotation
                
                previousX = currentX
                previousY = currentY
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

// MARK: - ContentView
struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var isImagePickerPresented = false
    
    var body: some View {
        ZStack {
            if let image = selectedImage {
                PanoramaView(image: image)
                    .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    Button(action: {
                        isImagePickerPresented = true
                    }) {
                        Text("选择其他全景图")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(10)
                    }
                    .padding(.bottom)
                }
            } else {
                VStack {
                    Image(systemName: "photo.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.gray)
                    
                    Button(action: {
                        isImagePickerPresented = true
                    }) {
                        Text("选择全景图")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
            }
        }
        .sheet(isPresented: $isImagePickerPresented) {
            ImagePicker(image: $selectedImage)
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

// MARK: - Previews
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
