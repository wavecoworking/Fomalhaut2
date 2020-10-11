import Cocoa
import XCGLogger

let log = XCGLogger.default

let pageLoadingOperationQueue: OperationQueue = {
  let queue = OperationQueue()
  queue.maxConcurrentOperationCount = 2
  return queue
}()

@main
class AppDelegate: NSObject, NSApplicationDelegate {

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    // Insert code here to initialize your application
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
  }

}
