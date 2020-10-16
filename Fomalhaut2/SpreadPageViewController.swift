// SPDX-License-Identifier: GPL-3.0-only

import Cocoa
import RxRelay
import RxSwift

enum PageOrder {
  case ltr, rtl
}

class SpreadPageViewController: NSViewController {
  private(set) var pageCount: BehaviorRelay<Int> = BehaviorRelay(value: 0)
  private(set) var pageOrder: PageOrder = .rtl
  private(set) var currentPageIndex: BehaviorRelay<Int> = BehaviorRelay(value: 0)
  private var firstImage: PublishSubject<NSImage> = PublishSubject<NSImage>()
  private var secondImage: PublishSubject<NSImage?> = PublishSubject<NSImage?>()
  private let disposeBag = DisposeBag()

  @IBOutlet weak var imageStackView: NSStackView!
  @IBOutlet weak var firstImageView: NSImageView!
  @IBOutlet weak var secondImageView: NSImageView!

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do view setup here.
    // TODO: Use NSStackView#setViews instead of use userInterfaceLayoutDirection for page order?
    self.imageStackView.userInterfaceLayoutDirection = .rightToLeft
    Observable.zip(self.firstImage, self.secondImage)
      .observeOn(MainScheduler.instance)
      .subscribe(onNext: { images in
        let firstImage: NSImage = images.0
        let secondImage: NSImage? = images.1
        let firstImageWidth = firstImage.representations.first!.pixelsWide
        let firstImageHeight = firstImage.representations.first!.pixelsHigh
        let secondImageWidth = secondImage?.representations.first!.pixelsWide
        let secondImageHeight = secondImage?.representations.first!.pixelsHigh
        let contentWidth =
          max(firstImageWidth, (secondImageWidth ?? 0)) * (secondImage != nil ? 2 : 1)
        let contentHeight = max(firstImageHeight, (secondImageHeight ?? 0))

        self.firstImageView.image = firstImage
        if secondImage != nil {
          self.secondImageView.image = secondImage
          self.secondImageView.isHidden = false
        } else {
          self.secondImageView.isHidden = true
        }
        log.debug("Content size = \(contentWidth) x \(contentHeight)")
        guard let window = self.view.window else {
          log.error("window is nil")
          return
        }
        window.contentAspectRatio = NSSize(width: contentWidth, height: contentHeight)
        // Set window size as screen size
        let rect = window.constrainFrameRect(
          NSRect(
            x: window.frame.origin.x, y: window.frame.origin.y, width: CGFloat(contentWidth),
            height: CGFloat(contentHeight)), to: NSScreen.main)
        window.setContentSize(NSSize(width: rect.size.width, height: rect.size.height))
      })
      .disposed(by: self.disposeBag)
  }

  override var representedObject: Any? {
    didSet {
      // Update the view, if already loaded.
      if let document = representedObject as? BookAccessible {
        self.pageCount.accept(document.pageCount())

        self.currentPageIndex.asObservable().subscribe(onNext: { (pageIndex) in
          log.info("start to load at \(pageIndex)")
          // TODO: Try to obtain image from cache not to use OperationQueue
          document.image(at: pageIndex) { (result) in
            switch result {
            case .success(let image):
              self.firstImage.onNext(image)
              log.debug("success to load image at \(pageIndex)")
            case .failure(let error):
              log.info("fail to laod image at \(pageIndex): \(error)")
              self.firstImage.onError(error)
            }
          }
          if pageIndex > 0 && pageIndex + 1 < self.pageCount.value {
            log.info("start to load at \(pageIndex + 1)")
            document.image(at: pageIndex + 1) { (result) in
              switch result {
              case .success(let image):
                self.secondImage.onNext(image)
                log.debug("success to load image at \(pageIndex + 1)")
              case .failure(let error):
                log.info("fail to laod image at \(pageIndex + 1): \(error)")
                self.secondImage.onError(error)
              }
            }
          } else {
            self.secondImage.onNext(nil)
          }
          // preload before increment page
          let preloadIndex = pageIndex > 0 && pageIndex + 1 < self.pageCount.value ? 2 : 1
          let preloadCount = 2
          (0..<preloadCount).forEach { (index) in
            if pageIndex + preloadIndex + index < self.pageCount.value {
              log.debug("start to preload at \(pageIndex + preloadIndex + index)")
              document.image(at: pageIndex + preloadIndex + index) { (_) in
                // do nothing
              }
            }
          }
        }).disposed(by: self.disposeBag)
      }
    }
  }

  override func mouseUp(with event: NSEvent) {
    log.info("mouseUp")
    self.forwardPage()
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
  }
}