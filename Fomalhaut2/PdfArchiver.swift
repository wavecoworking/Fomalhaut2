// SPDX-FileCopyrightText: 2020 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-only

import Cocoa
import PDFKit

class PdfArchiver: Archiver {
  static let utis: [String] = ["com.adobe.pdf"]
  private let pdfDocument: PDFDocument
  private let operationQueue = OperationQueue()

  init?(url: URL) {
    if let pdfDocument = PDFDocument(url: url) {
      self.pdfDocument = pdfDocument
    } else {
      return nil
    }
  }

  func pageCount() -> Int {
    return self.pdfDocument.pageCount
  }

  func image(at page: Int, completion: @escaping (Result<NSImage, BookAccessibleError>) -> Void) {
    self.operationQueue.addOperation {
      if let pdfPage = self.pdfDocument.page(at: page), let data = pdfPage.dataRepresentation,
        let imageRep = NSPDFImageRep(data: data)
      {
        let image = NSImage(size: imageRep.size)
        image.lockFocus()
        // Set background color for transparent PDF
        NSColor.white.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: imageRep.size))
        imageRep.draw(at: .zero)
        image.unlockFocus()
        //log.debug("pdf image size \(image.size.width)x\(image.size.height)")
        completion(.success(image))
      } else {
        log.info("Error while extracting at \(page)")
        completion(.failure(BookAccessibleError.brokenFile))
      }
    }
  }
}
