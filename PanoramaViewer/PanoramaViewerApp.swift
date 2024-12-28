//
//  PanoramaViewerApp.swift
//  PanoramaViewer
//
//  Created by sigma on 2024/12/27.
//

import SwiftUI
import SceneKit
import Photos

@main
struct PanoramaViewerApp: App {
    @StateObject private var mediaManager = PanoramaMediaManager()
    
    init() {
        // 确保在app启动时就请求权限
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mediaManager)
        }
    }
}
