import LiveKit
import SwiftUI

struct LiveVideoTrackView: UIViewRepresentable {
  let track: VideoTrack?
  var fillsFrame = false

  func makeUIView(context: Context) -> VideoView {
    let videoView = VideoView()
    videoView.layoutMode = fillsFrame ? .fill : .fit
    videoView.clipsToBounds = true
    videoView.backgroundColor = .black
    return videoView
  }

  func updateUIView(_ uiView: VideoView, context: Context) {
    uiView.layoutMode = fillsFrame ? .fill : .fit
    uiView.track = track
  }
}
