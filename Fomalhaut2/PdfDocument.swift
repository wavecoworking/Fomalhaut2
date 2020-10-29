// SPDX-License-Identifier: GPL-3.0-only

import Cocoa
import PDFKit

enum PdfError: Error {
  case unknown
}

class PdfDocument: BookDocument {
  static let UTI: String = "com.adobe.pdf"
  private var pdfDocument: PDFDocument?
  private var url: URL?
  private let operationQueue: OperationQueue = {
    let queue = OperationQueue()
    return queue
  }()

  override func read(from url: URL, ofType typeName: String) throws {
    if let pdf = PDFDocument(url: url) {
      self.pdfDocument = pdf
      self.url = url
    } else {
      throw NSError(domain: "net.mtgto.Fomalhaut2", code: 0, userInfo: nil)
    }
  }
}

extension PdfDocument: BookAccessible {
  func pageCount() -> Int {
    return self.pdfDocument!.pageCount
  }

  func image(at page: Int, completion: @escaping (Result<NSImage, Error>) -> Void) {
    let imageCacheKey = ImageCacheKey(archiveURL: self.url!, pageIndex: page)
    if let image = imageCache.object(forKey: imageCacheKey) {
      log.debug("success to load from cache at \(page)")
      completion(.success(image))
      return
    }
    self.operationQueue.addOperation {
      if let pdfPage = self.pdfDocument!.page(at: page), let data = pdfPage.dataRepresentation,
        let image = NSImage(data: data)
      {
        //log.debug("pdf image size \(image.size.width)x\(image.size.height)")
        if page == 0 && self.book!.thumbnailData == nil {
          do {
            try self.setBookThumbnail(image)
          } catch {
            log.error("Error while creating thumbnail: \(error)")
          }
        }
        completion(.success(image))
      } else {
        log.info("Error while extracting at \(page)")
        completion(.failure(PdfError.unknown))
      }
    }
  }

  func lastPageIndex() -> Int? {
    return self.book?.lastPageIndex
  }

  func lastPageOrder() -> PageOrder? {
    guard let book = self.book else {
      return nil
    }
    return book.isRightToLeft ? .rtl : .ltr
  }
}