import SwiftUI
import WatchConnectivity

@main
struct SwiftMusicWatchApp: App {
  @StateObject private var model = WatchPlayer()
  var body: some Scene {
    WindowGroup {
      ScrollView {
        VStack(spacing: 12) {
          Text(model.title).font(.headline).multilineTextAlignment(.center)
          Text(model.artist).font(.caption).foregroundStyle(.secondary)
          Text(model.status).font(.caption2).foregroundStyle(.secondary)
          HStack {
            Button { model.send("previous") } label: { Image(systemName: "backward.end.fill") }
              .accessibilityLabel("Lagu sebelumnya")
            Button { model.send(model.playing ? "pause" : "play") } label: {
              Image(systemName: model.playing ? "pause.fill" : "play.fill")
            }.tint(.green).accessibilityLabel(model.playing ? "Jeda" : "Putar")
            Button { model.send("next") } label: { Image(systemName: "forward.end.fill") }
              .accessibilityLabel("Lagu berikutnya")
          }
          Slider(value: $model.volume, in: 0...1, onEditingChanged: { editing in
            if !editing { model.send("volume", value: model.volume) }
          }).accessibilityLabel("Volume aplikasi")
          Button("Hubungkan ulang") { model.send("state") }.font(.caption)
        }.padding(.horizontal, 8)
      }.onAppear { model.send("state") }
    }
  }
}

final class WatchPlayer: NSObject, ObservableObject, WCSessionDelegate {
  @Published var title = "Swift Music"
  @Published var artist = ""
  @Published var playing = false
  @Published var volume = 1.0
  @Published var status = "Buka Swift Music di iPhone"
  override init() {
    super.init()
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }
  func send(_ action: String, value: Double? = nil) {
    let session = WCSession.default
    guard session.activationState == .activated, session.isReachable else {
      status = "iPhone belum terhubung • buka Swift Music"; return
    }
    var message: [String: Any] = ["action": action]
    if let value = value { message["value"] = value }
    session.sendMessage(message, replyHandler: { data in
      self.render(data, cached: false)
    }, errorHandler: { _ in
      DispatchQueue.main.async { self.status = "Koneksi terputus • coba kembali" }
    })
  }
  private func render(_ data: [String: Any], cached: Bool) {
    DispatchQueue.main.async {
      if let error = data["error"] as? String { self.status = error; return }
      self.title = data["title"] as? String ?? "Swift Music"
      self.artist = data["artist"] as? String ?? ""
      self.playing = data["playing"] as? Bool ?? false
      self.volume = min(1, max(0, data["volume"] as? Double ?? 1))
      let age = Date().timeIntervalSince1970 * 1000 - (data["updatedAt"] as? Double ?? 0)
      self.status = cached || age > 15000 ? "Status terakhir • hubungkan iPhone" : (self.playing ? "Diputar di iPhone" : "Dijeda di iPhone")
    }
  }
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    render(session.receivedApplicationContext, cached: true)
    DispatchQueue.main.async { self.send("state") }
  }
  func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async { self.send("state") }
  }
  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    render(applicationContext, cached: false)
  }
}
