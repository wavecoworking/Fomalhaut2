// SPDX-License-Identifier: GPL-3.0-only

import Cocoa
import RxSwift

class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
  private let disposeBag = DisposeBag()
  @IBOutlet weak var collectionViewStyleSegmentedControl: NSSegmentedControl!
  @IBOutlet weak var searchField: NSSearchField!

  override func windowDidLoad() {
    super.windowDidLoad()

    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    let splitViewController = self.contentViewController as! NSSplitViewController
    let mainViewController =
      splitViewController.splitViewItems[1].viewController as! MainViewController
    mainViewController.collectionViewStyle
      .observeOn(MainScheduler.instance)
      .subscribe(onNext: { collectionViewStyle in
        self.collectionViewStyleSegmentedControl.selectSegment(
          withTag: collectionViewStyle == .collection ? 0 : 1)
      })
      .disposed(by: self.disposeBag)
    self.searchField.rx.text.asDriver()
      .drive(onNext: { text in
        mainViewController.searchText.accept(text)
      })
      .disposed(by: self.disposeBag)
    // NOTE: windowFrameAutosaveName should be different from NSWindow's autosave name
    self.windowFrameAutosaveName = "MainWindowController"
  }

  @IBAction func updateCollectionViewStyle(_ sender: Any) {
    let splitViewController = self.contentViewController as! NSSplitViewController
    let mainViewController =
      splitViewController.splitViewItems[1].viewController as! MainViewController
    if let segmentedControl = sender as? NSSegmentedControl {
      if segmentedControl.selectedSegment == 0 {  // Use CollectionView
        mainViewController.setCollectionViewStyle(.collection)
      } else {  // Use TableView
        mainViewController.setCollectionViewStyle(.list)
      }
    }
  }

  // MARK: - MenuItem
  @IBAction func useThumbnailView(_ sender: Any) {
    let splitViewController = self.contentViewController as! NSSplitViewController
    let mainViewController =
      splitViewController.splitViewItems[1].viewController as! MainViewController
    mainViewController.setCollectionViewStyle(.collection)
  }

  @IBAction func useListView(_ sender: Any) {
    let splitViewController = self.contentViewController as! NSSplitViewController
    let mainViewController =
      splitViewController.splitViewItems[1].viewController as! MainViewController
    mainViewController.setCollectionViewStyle(.list)
  }

  // MARK: - NSMenuItemValidation
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    let splitViewController = self.contentViewController as! NSSplitViewController
    let mainViewController =
      splitViewController.splitViewItems[1].viewController as! MainViewController
    guard let selector = menuItem.action else {
      return false
    }
    if selector == #selector(useThumbnailView(_:)) {
      menuItem.state = mainViewController.collectionViewStyle.value == .collection ? .on : .off
      return true
    } else if selector == #selector(useListView(_:)) {
      menuItem.state = mainViewController.collectionViewStyle.value == .list ? .on : .off
      return true
    }
    return false
  }
}
