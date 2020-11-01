// SPDX-License-Identifier: GPL-3.0-only

import Cocoa
import RealmSwift
import RxRelay
import RxSwift

struct LoadedImage {
  let preload: Bool
  let images: [NSImage]
}

class SpreadPageViewController: NSViewController {
  let pageCount: BehaviorRelay<Int> = BehaviorRelay(value: 0)
  let pageOrder: BehaviorRelay<PageOrder> = BehaviorRelay(value: .rtl)
  let currentPageIndex: BehaviorRelay<Int> = BehaviorRelay(value: 0)
  // manualViewHeight has non-nil view height after user resized window
  private var manualViewHeight: CGFloat? = nil
  private let disposeBag = DisposeBag()

  @IBOutlet weak var imageStackView: NSStackView!
  @IBOutlet weak var firstImageView: NSImageView!
  @IBOutlet weak var secondImageView: NSImageView!

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
    // TODO: Use NSStackView#setViews instead of use userInterfaceLayoutDirection for page order?
    self.imageStackView.userInterfaceLayoutDirection = .rightToLeft
    // Set background color for transparent PDF
    self.view.wantsLayer = true
    self.view.layer?.backgroundColor = NSColor.white.cgColor
  }

  override func viewWillDisappear() {
    super.viewWillDisappear()
    // Update book state
    if let document = self.representedObject as? BookDocument {
      try? document.storeViewerStatus(
        lastPageIndex: self.currentPageIndex.value, isRightToLeft: self.pageOrder.value == .rtl)
    }
  }

  func fetchImages(pageIndex: Int, document: BookAccessible) -> Observable<LoadedImage> {
    return Observable.range(
      start: self.currentPageIndex.value,
      count: self.pageCount.value - self.currentPageIndex.value
    )
    .map { pageIndex in
      self.loadImage(pageIndex: pageIndex, document: document)
    }
    .concat()
    .buffer(timeSpan: .never, count: pageIndex == 0 ? 1 : 2, scheduler: MainScheduler.instance)
    .enumerated()
    .map { LoadedImage(preload: $0.index > 0, images: $0.element) }
  }

  override var representedObject: Any? {
    didSet {
      guard let document = representedObject as? BookAccessible else { return }
      self.pageCount.accept(document.pageCount())
      if let lastPageIndex = document.lastPageIndex() {
        self.currentPageIndex.accept(lastPageIndex)
      }
      if let lastPageOrder = document.lastPageOrder() {
        self.pageOrder.accept(lastPageOrder)
      }
      self.pageOrder
        .observeOn(MainScheduler.instance)
        .subscribe(onNext: { [unowned self] pageOrder in
          self.imageStackView.userInterfaceLayoutDirection =
            pageOrder == PageOrder.rtl ? .rightToLeft : .leftToRight
        })
        .disposed(by: self.disposeBag)
      self.currentPageIndex.flatMapLatest { (currentPageIndex) in
        self.fetchImages(pageIndex: currentPageIndex, document: document)
      }
      .observeOn(MainScheduler.instance)
      .subscribe(
        onNext: { (loadedImage) in
          //log.debug("image = \(loadedImage.images.count), prefetch = \(loadedImage.preload)")
          if loadedImage.preload || loadedImage.images.count == 0 {
            return
          }
          let images = loadedImage.images
          let firstImage: NSImage = images.first!  // TODO: It might be nil if all files are broken
          let secondImage: NSImage? = images.count >= 2 ? images.last : nil
          let firstImageSize = self.imageSize(firstImage)
          let secondImageSize = secondImage != nil ? self.imageSize(secondImage!) : nil
          let contentWidth =
            max(firstImageSize.width, (secondImageSize?.width ?? 0)) * (secondImage != nil ? 2 : 1)
          let contentHeight = max(firstImageSize.height, (secondImageSize?.height ?? 0))

          self.firstImageView.image = firstImage
          if secondImage != nil {
            self.secondImageView.image = secondImage
            self.secondImageView.isHidden = false
          } else {
            self.secondImageView.isHidden = true
          }
          guard let window = self.view.window else {
            log.error("window is nil")
            return
          }
          window.contentAspectRatio = NSSize(width: contentWidth, height: contentHeight)
          // Set window size as screen size
          let resizeRatio: CGFloat
          if let manualViewHeight = self.manualViewHeight {
            resizeRatio = manualViewHeight / contentHeight
          } else {
            resizeRatio = 1.0
          }
          let rect = window.constrainFrameRect(
            NSRect(
              x: window.frame.origin.x,
              y: window.frame.origin.y,
              width: CGFloat(contentWidth * resizeRatio),
              height: CGFloat(contentHeight * resizeRatio)), to: NSScreen.main)
          window.setContentSize(NSSize(width: rect.size.width, height: rect.size.height))
          window.setFrameOrigin(rect.origin)
          log.debug("window.setContentSize(\(rect.size.width), \(rect.size.height))")
        },
        onCompleted: {
          log.debug("onCompleted")
        }
      )
      .disposed(by: self.disposeBag)
    }
  }

  override func mouseUp(with event: NSEvent) {
    self.forwardPage()
  }

  override func encodeRestorableState(with coder: NSCoder) {
    super.encodeRestorableState(with: coder)
    coder.encode(self.currentPageIndex.value, forKey: "currentPageIndex")
  }

  override func restoreState(with coder: NSCoder) {
    super.restoreState(with: coder)
    let lastCurrentPageIndex = coder.decodeInteger(forKey: "currentPageIndex")
    self.currentPageIndex.accept(lastCurrentPageIndex)
  }

  private func imageSize(_ image: NSImage) -> NSSize {
    let width = image.representations.first!.pixelsWide
    let height = image.representations.first!.pixelsHigh
    if width == 0 && height == 0 {
      return image.size
    } else {
      return NSSize(width: width, height: height)
    }
  }

  func loadImage(pageIndex: Int, document: BookAccessible) -> Observable<NSImage> {
    return Observable<NSImage>.create { observer in
      document.image(at: pageIndex) { (result) in
        switch result {
        case .success(let image):
          observer.onNext(image)
          observer.onCompleted()
          log.debug("success to load image at \(pageIndex)")
        case .failure(let error):
          // do nothing (= skip broken page)
          // TODO: Remember error index in ZipDocument not to reload same error page
          // observer.onError(error)
          log.info("fail to load image at \(pageIndex): \(error)")
          observer.onCompleted()
        }
      }
      return Disposables.create()
    }
  }

  // increment page (two page increment)
  func forwardPage() {
    let incremental = self.currentPageIndex.value == 0 ? 1 : 2
    if self.currentPageIndex.value + incremental < self.pageCount.value {
      self.currentPageIndex.accept(self.currentPageIndex.value + incremental)
    }
  }

  func forwardSinglePage() {
    if self.canForwardPage() {
      self.currentPageIndex.accept(self.currentPageIndex.value + 1)
    }
  }

  // decrement page (two page decrement)
  func backwardPage() {
    let decremental = self.currentPageIndex.value == 1 ? 1 : 2
    if self.currentPageIndex.value - decremental >= 0 {
      self.currentPageIndex.accept(self.currentPageIndex.value - decremental)
    }
  }

  func backwardSinglePage() {
    if self.canBackwardPage() {
      self.currentPageIndex.accept(self.currentPageIndex.value - 1)
    }
  }

  func canForwardPage() -> Bool {
    return self.currentPageIndex.value + 1 < self.pageCount.value
  }

  func canBackwardPage() -> Bool {
    return self.currentPageIndex.value - 1 >= 0
  }

  func setPageOrder(_ pageOrder: PageOrder) {
    self.imageStackView.userInterfaceLayoutDirection =
      pageOrder == .rtl ? .rightToLeft : .leftToRight
    self.pageOrder.accept(pageOrder)
  }

  func resizedWindowByManual() {
    self.manualViewHeight = self.view.frame.size.height
  }
}
