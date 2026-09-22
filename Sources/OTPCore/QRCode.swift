import CoreImage
import Foundation
import Vision

/// 이미지에서 QR 내용을 읽는다. 전부 로컬에서 처리하며 어디에도 전송하지 않는다.
public enum QRCode {
    /// 이미지 데이터에서 발견한 QR 문자열을 모두 반환한다.
    public static func decode(imageData: Data) throws -> [String] {
        guard let image = CIImage(data: imageData) else {
            throw OTPError("이미지를 읽을 수 없습니다. PNG·JPEG·TIFF 를 지원합니다.")
        }
        return try decode(image: image)
    }

    public static func decode(fileURL: URL) throws -> [String] {
        guard let image = CIImage(contentsOf: fileURL) else {
            throw OTPError("이미지를 읽을 수 없습니다: \(fileURL.path)")
        }
        return try decode(image: image)
    }

    private static func decode(image: CIImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OTPError("QR 인식에 실패했습니다: \(error.localizedDescription)")
        }

        let payloads = (request.results ?? []).compactMap { $0.payloadStringValue }
        guard !payloads.isEmpty else {
            throw OTPError("이미지에서 QR 코드를 찾지 못했습니다. QR 전체가 또렷하게 담기도록 다시 캡처해보세요.")
        }
        return payloads
    }

    /// 검증용 QR 생성. 등록 흐름을 실제 이미지로 자체 검사하는 데 쓴다.
    public static func generate(from text: String) -> Data? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        // 인식률을 위해 충분히 키운다
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}

#if canImport(AppKit)
    import AppKit
#endif
