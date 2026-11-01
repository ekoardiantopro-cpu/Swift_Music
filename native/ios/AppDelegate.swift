import Flutter
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import ImageIO
import AudioToolbox
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var musicFolders: MusicFolderBridge?
  private var systemChannel: FlutterMethodChannel?
  private var watchBridge: SwiftWatchBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    watchBridge = SwiftWatchBridge(messenger: engineBridge.applicationRegistrar.messenger())
    systemChannel = FlutterMethodChannel(name: "com.swiftmusic/system", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    systemChannel?.setMethodCallHandler { call, result in
      if call.method == "keepAwake" {
        let args = call.arguments as? [String: Any] ?? [:]
        UIApplication.shared.isIdleTimerDisabled = args["enabled"] as? Bool ?? false
        result(nil)
      } else { result(FlutterMethodNotImplemented) }
    }
    musicFolders = MusicFolderBridge(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

/// Keeps only the latest snapshot, so reconnecting never replays old commands.
private final class SwiftWatchBridge: NSObject, WCSessionDelegate {
  private let channel: FlutterMethodChannel
  private var latest = [String: Any]()
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.swiftmusic/watch", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      guard call.method == "publish", let data = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented); return
      }
      self.latest = data
      self.publish()
      result(nil)
    }
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }
  private func publish() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
    try? session.updateApplicationContext(latest)
  }
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async { self.publish() }
  }
  func sessionDidBecomeInactive(_ session: WCSession) {}
  func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    let action = message["action"] as? String ?? ""
    guard ["state", "play", "pause", "next", "previous", "seek", "volume"].contains(action) else {
      replyHandler(["error": "Unsupported command"]); return
    }
    var args: [String: Any] = ["action": action]
    if let value = message["value"] as? NSNumber { args["value"] = value }
    DispatchQueue.main.async {
      self.channel.invokeMethod("command", arguments: args) { result in
        if let data = result as? [String: Any] { replyHandler(data) }
        else { replyHandler(["error": "Buka Swift Music di iPhone"] ) }
      }
    }
  }
}

/// Keeps security-scoped access only while copying the selected folder.
private final class MusicFolderBridge: NSObject, UIDocumentPickerDelegate {
  private let worker = DispatchQueue(label: "com.swiftmusic.folder-io", qos: .utility)
  private var pending: FlutterResult?
  private var folder: URL?
  private var hasScope = false
  private var allowed = Set<String>()
  private var handles = [Int: FileHandle]()
  private var nextHandle = 0
  private var channel: FlutterMethodChannel!
  private var metadataChannel: FlutterMethodChannel!

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    metadataChannel = FlutterMethodChannel(name: "com.swiftmusic/metadata", binaryMessenger: messenger)
    metadataChannel.setMethodCallHandler { [self] call, result in
      guard call.method == "read" else { result(FlutterMethodNotImplemented); return }
      worker.async { [self] in
        do {
          let tags = try readMetadata(call)
          DispatchQueue.main.async { result(tags) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "metadata", message: error.localizedDescription, details: nil)) }
        }
      }
    }
    channel = FlutterMethodChannel(name: "com.swiftmusic/music_folders", binaryMessenger: messenger)
    channel.setMethodCallHandler { [self] call, result in
      if call.method == "pickFolder" { pick(result); return }
      guard ["listFolder", "openFile", "readChunk", "closeFile", "releaseFolder", "restoreFolder", "forgetFolder"].contains(call.method) else {
        result(FlutterMethodNotImplemented); return
      }
      worker.async { [self] in
        do {
          let value = try handle(call)
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "folder_io", message: error.localizedDescription, details: nil)) }
        }
      }
    }
  }

  private func readMetadata(_ call: FlutterMethodCall) throws -> [String: Any] {
    let args = call.arguments as? [String: Any] ?? [:]
    guard let path = args["path"] as? String, let coverPath = args["coverPath"] as? String else { throw FolderError.notAllowed }
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("local_music").standardizedFileURL.resolvingSymlinksInPath()
    let audio = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    let cover = URL(fileURLWithPath: coverPath).standardizedFileURL.resolvingSymlinksInPath()
    guard audio.deletingLastPathComponent() == root, cover.deletingLastPathComponent() == root else { throw FolderError.notAllowed }
    let asset = AVURLAsset(url: audio)
    var tags = [String: Any]()
    for item in asset.commonMetadata {
      if let key = item.commonKey?.rawValue, ["title", "artist", "albumName", "type"].contains(key), let value = item.stringValue {
        tags[key == "albumName" ? "album" : key == "type" ? "genre" : key] = value
      }
      if item.commonKey == .commonKeyArtwork, let data = item.dataValue, data.count <= 8 * 1024 * 1024,
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 768,
          kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary) {
        try UIImage(cgImage: image).jpegData(compressionQuality: 0.82)?.write(to: cover, options: .atomic)
      }
    }
    let seconds = CMTimeGetSeconds(asset.duration)
    if let audioTrack = asset.tracks(withMediaType: .audio).first {
      tags["bitrate"] = Int(audioTrack.estimatedDataRate)
      if let description = audioTrack.formatDescriptions.first {
        let format = description as! CMAudioFormatDescription
        if let details = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
          tags["sampleRate"] = details.mSampleRate
          tags["bitsPerSample"] = details.mBitsPerChannel
          tags["channels"] = details.mChannelsPerFrame
        }
      }
    }
    for item in asset.metadata {
      let identifier = item.identifier?.rawValue.lowercased() ?? ""
      guard let value = item.stringValue else { continue }
      if identifier.contains("composer") || identifier.contains("tcom") { tags["composer"] = value }
      if identifier.contains("writer") || identifier.contains("text") { tags["writer"] = value }
      if identifier.contains("year") || identifier.contains("tdrc") || identifier.contains("tyer") { tags["year"] = value }
      if identifier.contains("trck") || identifier.contains("tracknumber") { tags["track"] = value }
      if identifier.contains("tpos") || identifier.contains("discnumber") { tags["disc"] = value }
      if identifier.contains("bpm") || identifier.contains("tbpm") { tags["bpm"] = value }
      if identifier.contains("tkey") { tags["key"] = value }
      if identifier.contains("publisher") || identifier.contains("tpub") { tags["label"] = value }
    }
    if seconds.isFinite && seconds > 0 { tags["durationMs"] = Int(seconds * 1000) }
    return tags
  }

  private func pick(_ result: @escaping FlutterResult) {
    guard pending == nil else { result(FlutterError(code: "picker_busy", message: "Pemilih folder sedang dibuka.", details: nil)); return }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard var presenter = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "folder_picker", message: "Jendela aplikasi tidak tersedia.", details: nil)); return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    pending = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pending?(nil); pending = nil
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { documentPickerWasCancelled(controller); return }
    folder = url
    hasScope = url.startAccessingSecurityScopedResource()
    let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    pending?(["uri": url.absoluteString, "name": url.lastPathComponent, "bookmark": bookmark?.base64EncodedString() ?? ""])
    pending = nil
  }

  private func handle(_ call: FlutterMethodCall) throws -> Any? {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "restoreFolder":
      guard let encoded = args["bookmark"] as? String, let data = Data(base64Encoded: encoded) else { throw FolderError.notAllowed }
      var stale = false
      let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
      folder = url
      hasScope = url.startAccessingSecurityScopedResource()
      let renewed = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
      return ["uri": url.absoluteString, "name": url.lastPathComponent, "bookmark": renewed.base64EncodedString()]
    case "forgetFolder": return nil
    case "listFolder":
      guard let root = folder else { throw FolderError.notSelected }
      let extensions = Set(args["extensions"] as? [String] ?? [])
      let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
      guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw FolderError.notSelected }
      allowed.removeAll()
      var files = [[String: Any]]()
      for case let url as URL in entries {
        let values = try url.resourceValues(forKeys: Set(keys))
        guard values.isRegularFile == true, values.isSymbolicLink != true,
          extensions.contains(url.pathExtension.lowercased()) else { continue }
        allowed.insert(url.absoluteString)
        files.append(["uri": url.absoluteString, "name": url.lastPathComponent,
          "size": values.fileSize ?? -1, "modifiedMs": Int((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000)])
      }
      return files
    case "openFile":
      guard let uri = args["uri"] as? String, allowed.contains(uri), let url = URL(string: uri) else {
        throw FolderError.notAllowed
      }
      nextHandle += 1
      handles[nextHandle] = try FileHandle(forReadingFrom: url)
      return nextHandle
    case "readChunk":
      guard let id = args["handle"] as? Int, let file = handles[id] else { throw FolderError.missingHandle }
      guard let bytes = try file.read(upToCount: 65536), !bytes.isEmpty else { return nil }
      return FlutterStandardTypedData(bytes: bytes)
    case "closeFile":
      if let id = args["handle"] as? Int { try handles.removeValue(forKey: id)?.close() }
      return nil
    case "releaseFolder":
      for file in handles.values { try? file.close() }
      handles.removeAll(); allowed.removeAll()
      if hasScope { folder?.stopAccessingSecurityScopedResource() }
      folder = nil; hasScope = false
      return nil
    default: return FlutterMethodNotImplemented
    }
  }
  private enum FolderError: Error { case notSelected, notAllowed, missingHandle }
}
