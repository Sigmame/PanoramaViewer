import SwiftUI

struct LongPressShareModifier: ViewModifier {
    let asset: PHAsset
    let mediaManager: PanoramaMediaManager
    @State private var isShowingShareSheet = false
    @State private var shareItems: [Any] = []
    
    func body(content: Content) -> some View {
        content
            .onLongPressGesture {
                mediaManager.prepareForSharing(asset: asset) { items, error in
                    if let error = error {
                        print("Error preparing for sharing: \(error)")
                        return
                    }
                    shareItems = items
                    isShowingShareSheet = true
                }
            }
            .sheet(isPresented: $isShowingShareSheet) {
                if !shareItems.isEmpty {
                    ActivityViewController(activityItems: shareItems)
                }
            }
    }
}

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

extension View {
    func longPressShare(asset: PHAsset, mediaManager: PanoramaMediaManager) -> some View {
        modifier(LongPressShareModifier(asset: asset, mediaManager: mediaManager))
    }
} 