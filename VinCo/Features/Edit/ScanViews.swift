import SwiftUI
import VisionKit
import Vision
import UIKit

// MARK: – Barcode scanner sheet
// Full-screen live barcode scanner using DataScannerViewController (iOS 17+).
// Fires onDetected exactly once with the raw barcode payload string.
struct BarcodeScannerSheet: View {
    let onDetected: (String) -> Void
    let onCancel:   () -> Void
    @Environment(Settings.self) private var settings

    var body: some View {
        ZStack(alignment: .top) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                _BarcodeScannerVC(onDetected: onDetected)
                    .ignoresSafeArea()

                // Instruction pill
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 15))
                        Text("Point at the barcode on the sleeve")
                            .font(Theme.courier(13))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.bottom, 48)
                }
            } else {
                // Fallback: device doesn't support DataScannerViewController
                ZStack {
                    settings.bg0.ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 56))
                            .foregroundStyle(Theme.textT)
                        Text("Barcode scanning is not\navailable on this device")
                            .font(Theme.courier(15))
                            .foregroundStyle(Theme.textS)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            // Top bar: Cancel + title
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text("SCAN BARCODE")
                    .font(Theme.courier(12, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.black.opacity(0.45))
                    .clipShape(Capsule())
                Spacer()
                // Balance the cancel button
                Circle().fill(.clear).frame(width: 36, height: 36)
            }
            .padding(.top, 60)
            .padding(.horizontal, 20)
        }
    }
}

// MARK: – DataScannerViewController wrapper
private struct _BarcodeScannerVC: UIViewControllerRepresentable {
    let onDetected: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39, .qr])
            ],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDetected: onDetected) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onDetected: (String) -> Void
        private var fired = false

        init(onDetected: @escaping (String) -> Void) { self.onDetected = onDetected }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !fired else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let val = b.payloadStringValue {
                    fired = true
                    // Brief haptic feedback on successful scan
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDetected(val)
                    return
                }
            }
        }
    }
}

// MARK: – Camera capture view for album cover
// Presents UIImagePickerController in camera mode and returns JPEG data.
struct CoverCameraView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    let onCancel:  () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType     = .camera
        picker.allowsEditing  = false
        picker.delegate       = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data) -> Void
        let onCancel:  () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture; self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage,
               let data = img.jpegData(compressionQuality: 0.85) {
                onCapture(data)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}

// MARK: – Vision text recognition helper
// Extracts the most prominent text lines from an image (e.g. an album cover or screenshot)
// and returns them joined as a Discogs search query.
nonisolated func recognizeAlbumText(from data: Data) async -> String {
    guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else { return "" }
    return await withCheckedContinuation { continuation in
        let request = VNRecognizeTextRequest { req, _ in
            let lines = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            // Top lines have the highest confidence — typically artist + album on a cover
            let query = lines.prefix(5).joined(separator: " ")
            continuation.resume(returning: query)
        }
        request.recognitionLevel       = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
}
