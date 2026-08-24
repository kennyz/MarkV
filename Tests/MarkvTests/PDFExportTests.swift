import CoreText
import Foundation
import PDFKit
import Testing
@testable import Markv

@MainActor
@Test func longVectorDocumentPaginatesToCompactA4PDF() throws {
    let sourceHeight: CGFloat = 20_000
    let sourceData = try makeLongVectorPDF(width: 900, height: sourceHeight)
    let paginated = try MarkvPDFExporter.paginate(sourceData)
    let document = try #require(PDFDocument(data: paginated))

    #expect(document.pageCount > 10)
    #expect(paginated.count < 1_500_000)

    let firstPage = try #require(document.page(at: 0))
    let lastPage = try #require(document.page(at: document.pageCount - 1))
    let bounds = firstPage.bounds(for: .mediaBox)
    #expect(abs(bounds.width - 595.28) < 2)
    #expect(abs(bounds.height - 841.89) < 2)
    #expect(firstPage.string?.contains("Top of document") == true)
    #expect(lastPage.string?.contains("Bottom of document") == true)

    if ProcessInfo.processInfo.environment["MARKV_KEEP_PDF"] == "1" {
        let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tmp/pdfs", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try paginated.write(
            to: outputDirectory.appendingPathComponent("markv-export-regression.pdf"),
            options: .atomic
        )
    }
}

private func makeLongVectorPDF(width: CGFloat, height: CGFloat) throws -> Data {
    let output = NSMutableData()
    guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
        throw PDFExportError.failed
    }
    var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw PDFExportError.failed
    }

    context.beginPDFPage(nil)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(mediaBox)
    context.setStrokeColor(CGColor(gray: 0.75, alpha: 1))
    context.setLineWidth(1)

    for y in stride(from: CGFloat(120), to: height, by: 120) {
        context.move(to: CGPoint(x: 70, y: y))
        context.addLine(to: CGPoint(x: width - 70, y: y))
        context.strokePath()
    }

    drawText("Bottom of document", at: CGPoint(x: 70, y: 45), in: context)
    drawText("Top of document", at: CGPoint(x: 70, y: height - 75), in: context)
    context.endPDFPage()
    context.closePDF()

    guard output.length > 0 else { throw PDFExportError.failed }
    return output as Data
}

private func drawText(_ text: String, at point: CGPoint, in context: CGContext) {
    let font = CTFontCreateWithName("Helvetica" as CFString, 28, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.18, alpha: 1)
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    context.textPosition = point
    CTLineDraw(line, context)
}
