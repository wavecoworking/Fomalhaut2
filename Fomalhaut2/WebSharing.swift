// SPDX-FileCopyrightText: 2020 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-only

import Cocoa
import NIO
import RealmSwift
import RxRealm
import RxRelay
import RxSwift
import Swiftra
import ZIPFoundation

private let cacheControlKey = "Cache-Control"
private let noCache = "no-cache"
private let contentTypeJpeg = "image/jpeg"

class WebSharing: NSObject {
  private let server = App()
  private(set) var started: Bool = false
  private var collections: [Collection] = []
  private var books: [Book] = []
  private let cache = NSCache<NSString, CombineArchiver>()
  private let assetArchive: Archive
  private let disposeBag = DisposeBag()
  private let notFound = Response(text: "Not Found", status: .notFound)
  private let internalServerError = Response(text: "Internal Server Error", status: .internalServerError)

  enum WebServerError: Error {
    case badBookURL
    case notFoundAsset
  }

  override init() {
    let assetsURL = Bundle.main.url(forResource: "assets", withExtension: "zip")!
    self.assetArchive = Archive(url: assetsURL, accessMode: .read)!
    self.cache.countLimit = 1
    super.init()
    self.server.addRoutes {
      futureGet("/") { req in
        self.defaultHtml(req)
      }

      futureGet("/books/:id") { req in
        self.defaultHtml(req)
      }

      futureGet("/collections/:id") { req in
        self.defaultHtml(req)
      }

      futureGet("/assets/:filename") { req in
        guard let filename = req.params("filename") else {
          return req.eventLoop.makeSucceededFuture(self.notFound)
        }
        let contentType: String
        if filename.hasSuffix(".js") {
          contentType = "text/javascript; charset=utf-8"
        } else if filename.hasSuffix(".map") {
          contentType = ContentType.applicationJson.withCharset()
        } else if filename.hasSuffix(".ico") {
          contentType = "image/x-ico"
        } else {
          contentType = ContentType.applicationOctetStream.rawValue
        }
        return self.loadAsset(filename, request: req)
          .map { Response(data: $0, contentType: contentType) }
      }

      get("/api/v1/collections") { req in
        Response(json: self.collections, headers: [(cacheControlKey, noCache)]) ?? self.internalServerError
      }

      get("/api/v1/collections/:id") { req in
        guard let collection = self.collections.first(where: { $0.id == req.params("id") }) else {
          return self.notFound
        }
        return Response(json: collection, headers: [(cacheControlKey, noCache)]) ?? self.internalServerError
      }

      get("/api/v1/books") { req in
        Response(json: self.books, headers: [(cacheControlKey, noCache)]) ?? self.internalServerError
      }

      get("/images/books/:id/thumbnail") { req in
        guard let book = self.books.first(where: { $0.id == req.params("id") }) else {
          return self.notFound
        }
        if let thumbnail = book.thumbnailData {
          return Response(
            data: thumbnail, contentType: contentTypeJpeg, headers: [(cacheControlKey, "private, max-age=1440")])
        } else {
          let url = Bundle.main.url(forResource: "defaultThumbnail", withExtension: "jpg")!
          let data = try! Data(contentsOf: url)
          return Response(data: data, contentType: contentTypeJpeg, headers: [(cacheControlKey, "private, max-age=60")])
        }
      }

      futureGet("/images/books/:id/pages/:page") { req in
        let promise = req.eventLoop.makePromise(of: Response.self)
        guard let book = self.books.first(where: { $0.id == req.params("id") }) else {
          promise.succeed(self.notFound)
          return promise.futureResult
        }
        let page = req.params("page").flatMap { Int($0) } ?? 0
        guard let archiver: Archiver = self.archiver(from: book) else {
          promise.succeed(self.internalServerError)
          return promise.futureResult
        }
        if page < 0 || archiver.pageCount() <= page {
          promise.succeed(self.notFound)
          return promise.futureResult
        }
        archiver.image(at: page) { (result) in
          switch result {
          case .success(let image):
            let data = image.resizedImageFixedAspectRatio(maxPixelsWide: 1024, maxPixelsHigh: 1024)!
            promise.succeed(
              Response(data: data, contentType: contentTypeJpeg, headers: [(cacheControlKey, "private, max-age=1440")]))
          case .failure(let error):
            log.warning("Fail to resize image: \(error)")
            promise.succeed(self.internalServerError)
          }
        }
        return promise.futureResult
      }
    }

    Schema.shared.state
      .skip { $0 != .finish }
      .withUnretained(self)
      .subscribe(onNext: { owner, _ in
        owner.setup()
      })
      .disposed(by: self.disposeBag)
  }

  func start(port: Int = 8080) throws {
    try self.server.start(port)
    log.info("WebServer started. port = \(port)")
    self.started = true
  }

  func stop(callback: ((Error?) -> Void)? = nil) {
    if self.started {
      self.server.stop { (error) in
        log.info("WebServer is stopped")
        self.started = false
        callback?(error)
      }
      log.info("WebServer is stopping.")
    }
  }

  private func setup() {
    let realm = try! Realm()
    Observable.array(from: realm.objects(Collection.self).sorted(byKeyPath: "createdAt", ascending: true))
      .withUnretained(self)
      .subscribe(onNext: { owner, collections in
        owner.collections = collections.map { $0.freeze() }
      })
      .disposed(by: self.disposeBag)
    Observable.array(from: realm.objects(Book.self).sorted(byKeyPath: "createdAt"))
      .withUnretained(self)
      .subscribe(onNext: { owner, books in
        owner.books = books.map { $0.freeze() }
      })
      .disposed(by: self.disposeBag)
  }

  private func defaultHtml(_ request: Request) -> EventLoopFuture<Response> {
    return self.loadAsset("index.html", request: request)
      .map { Response(data: $0, contentType: ContentType.textHtml.withCharset()) }
      .recover { _ in Response(text: "Error", status: .notFound, contentType: ContentType.textPlain.withCharset()) }
  }

  private func loadAsset(_ filename: String, request: Request) -> EventLoopFuture<Data> {
    let promise = request.eventLoop.makePromise(of: Data.self)
    guard let entry = self.assetArchive[filename] else {
      promise.fail(WebServerError.notFoundAsset)
      return promise.futureResult
    }
    var data: Data = Data()
    do {
      _ = try self.assetArchive.extract(
        entry, bufferSize: UInt32(entry.uncompressedSize), skipCRC32: true, progress: nil
      ) { (html) in
        data.append(html)
      }
      promise.succeed(data)
    } catch {
      log.warning("Error while loading asset \(filename): \(error)")
      promise.fail(error)
    }
    return promise.futureResult
  }

  private func archiver(from book: Book) -> Archiver? {
    if let archiver = self.cache.object(forKey: book.id as NSString) {
      return archiver
    }
    var bookmarkDataIsStale: Bool = false
    guard let url = try? book.resolveURL(bookmarkDataIsStale: &bookmarkDataIsStale) else {
      log.error("Error while resolve URL from a book")
      return nil
    }
    _ = url.startAccessingSecurityScopedResource()
    do {
      let typeName = try NSDocumentController.shared.typeForContents(of: url)
      if let archiver = CombineArchiver(from: url, ofType: typeName) {
        self.cache.setObject(archiver, forKey: book.id as NSString)
        return archiver
      }
    } catch {
      log.error("Error while getting type from file: \(error)")
    }
    return nil
  }
}

// MARK: - NSCacheDelegate
extension WebSharing: NSCacheDelegate {
  func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
    if let document = obj as? NSDocument {
      document.fileURL?.stopAccessingSecurityScopedResource()
    }
  }
}
