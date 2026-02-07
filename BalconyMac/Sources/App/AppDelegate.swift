import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("BalconyMac launched")
        // TODO: Initialize SessionMonitor
        // TODO: Start WebSocket server
        // TODO: Start Bonjour advertiser
        // TODO: Start BLE peripheral
        // TODO: Install Claude Code hooks
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("BalconyMac terminating")
        // TODO: Clean up hooks
        // TODO: Stop servers
    }
}
