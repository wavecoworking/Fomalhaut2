// SPDX-FileCopyrightText: 2020 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-only

import Cocoa
import ZIPFoundation

class ZipArchiver: Archiver {
  static let utis: [String] = ["com.pkware.zip-archive", "net.mtgto.Fomalhaut2.cbz"]
  private let archive: Archive
  private let entries: [Entry]
  private let operationQueue: OperationQueue

  init?(url: URL) {
    guard let archive = Archive(url: url, accessMode: .read, preferredEncoding: .shiftJIS) else {
      return nil
    }
    self.archive = archive
    self.entries = archive.sorted { (lhs, rhs) -> Bool in
      lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
    }.filter { (entry) -> Bool in
      if entry.path.contains("__MACOSX/") || entry.uncompressedSize == 0 {
        return false
      }
      let path = entry.path.lowercased()
      return path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") || path.hasSuffix(".png")
        || path.hasSuffix(".gif") || path.hasSuffix(".bmp")
    }
    self.operationQueue = OperationQueue()
    self.operationQueue.maxConcurrentOperationCount = 1
  }

  func pageCount() -> Int {
    return self.entries.count
  }

  func image(at page: Int, completion: @escaping (Result<NSImage, BookAccessibleError>) -> Void) {
    self.operationQueue.addOperation {
      let entry = self.entries[page]
      var rawData = Data()
      do {
        // Set bufferSize as uncomressed size to reduce the number of calls closure.
        // TODO: assert max bufferSize
        _ = try self.archive.extract(entry, bufferSize: UInt32(max(entry.uncompressedSize, 1)), skipCRC32: true) {
          (data) in
          // log.debug("size of data = \(data.count)")
          rawData.append(data)
          if rawData.count >= entry.uncompressedSize {
            guard let image = NSImage(data: rawData) else {
              completion(.failure(BookAccessibleError.brokenFile))
              return
            }
            completion(.success(image))
          }
        }
      } catch {
        log.info("Error while extracting at \(page): \(error)")
        completion(.failure(BookAccessibleError.brokenFile))
      }
    }
  }
}
