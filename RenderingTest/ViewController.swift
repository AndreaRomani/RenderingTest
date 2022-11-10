import AVKit
import UIKit

final class ViewController: AVPlayerViewController {
  private let url: URL
  private let asset: AVURLAsset
  private let videoTrack: AVAssetTrack
  private let audioTrack: AVAssetTrack

  override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
    let url = Bundle.main.url(forResource: "video", withExtension: "mp4")!
    let asset = AVURLAsset(url: url)

    self.url = url
    self.asset = asset
    self.videoTrack = asset.tracks(withMediaType: .video).first!
    self.audioTrack = asset.tracks(withMediaType: .audio).first!

    super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    // It looks like `MTAudioProcessingTapGetSourceAudio` doesn't work correctly when tapping re-scaled audio tracks
    // on an `AVComposition`. The simplest case identified is the following:
    // - composition with two audio tracks
    //  - first track has a single segment
    //  - second track has two segments:
    //    - first segment: empty
    //    - second segment: scaled and NOT at the beginning of the composition
    //  - the segment of the first track and the second segment of the second track
    //    can even overlap, but are kept separated in this demo for simplicity
    // See `Compositions` below for other working track arrangements
    let composition = self.twoAudioTracks
    let playerItem = AVPlayerItem(asset: composition)
    playerItem.audioMix = self.audioMix(for: composition)

    self.player = AVPlayer(playerItem: playerItem)
    self.view.backgroundColor = .yellow
  }
}

extension ViewController {
  /// A stub of an `AVAudioMix` that uses `MTAudioProcessingTap`.
  ///
  /// The `process` callback just extracts the source audio and renders it unaltered.
  /// It's not meant to describe a real use case of the audio tap, but just to show the problem.
  private func audioMix(for composition: AVComposition) -> AVAudioMix {
    let audioMix = AVMutableAudioMix()

    audioMix.inputParameters = composition.tracks(withMediaType: .audio).map { audioTrack in
      let trackInputParameters = AVMutableAudioMixInputParameters(track: audioTrack)
      trackInputParameters.audioTimePitchAlgorithm = .varispeed

      var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: nil
      ) { _, _, _ in
      } finalize: { _ in
      } prepare: { _, _, _ in
      } unprepare: { _ in
      } process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
        var timeRange: CMTimeRange = .invalid
        guard noErr == MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, &timeRange, numberFramesOut) else {
          return
        }
        // TimeRange is off when audio disappears
        print(timeRange)
      }

      var tap: Unmanaged<MTAudioProcessingTap>?
      let error = MTAudioProcessingTapCreate(
        kCFAllocatorDefault,
        &callbacks,
        kMTAudioProcessingTapCreationFlag_PostEffects,
        &tap
      )
      assert(error == noErr)
      trackInputParameters.audioTapProcessor = tap?.takeUnretainedValue()
      tap?.release()
      return trackInputParameters
    }
    return audioMix
  }
}

// MARK: - Compositions

extension ViewController {
  // source: 1s -> 3s ---> target: 0s -> 2s (speed = 1)
  private var segment1: CMTimeMapping {
    CMTimeMapping(
      source: CMTimeRange(start: .seconds(1), duration: .seconds(2)),
      target: CMTimeRange(start: .seconds(0), duration: .seconds(2))
    )
  }

  // source: 3s -> 5s ---> target: 2s -> 6s (speed = 0.5)
  private var segment2: CMTimeMapping {
    CMTimeMapping(
      source: CMTimeRange(start: .seconds(3), duration: .seconds(2)),
      target: CMTimeRange(start: .seconds(2), duration: .seconds(4))
    )
  }

  /// Two audio tracks: NOT OK
  // time:   0s------1s------2s------3s------4s------5s------6s
  // source: |-------[xxxxxxxxxxxxxxx][yyyyyyyyyyyyyy]
  // track1: [xxxxxxxxxxxxxxx]
  // track2: |----------------[ y y y y y y y   y y y y y y y]
  private var twoAudioTracks: AVComposition {
    let composition = AVMutableComposition()
    self.addVideoTrack(to: composition)
    let compositionAudioTrack1 = composition.addMutableTrack(
      withMediaType: .audio, preferredTrackID:
        kCMPersistentTrackID_Invalid
    )!
    try! compositionAudioTrack1.insertTimeRange(self.segment1.source, of: self.audioTrack, at: .zero)

    let compositionAudioTrack2 = composition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )!
    try! compositionAudioTrack2.insertTimeRange(self.segment2.source, of: self.audioTrack, at: self.segment2.target.start)
    compositionAudioTrack2.scaleTimeRange(
      CMTimeRange(start: self.segment2.target.start, duration: self.segment2.source.duration),
      toDuration: self.segment2.target.duration
    )
    return composition
  }

  /// Two audio tracks swapped: OK
  // time:   0s------1s------2s------3s------4s------5s------6s
  // source: |-------[xxxxxxxxxxxxxxx][yyyyyyyyyyyyyy]
  // track1: |----------------[ y y y y y y y   y y y y y y y]
  // track2: [xxxxxxxxxxxxxxx]
  private var twoAudioTracksSwapped: AVComposition {
    let composition = AVMutableComposition()
    self.addVideoTrack(to: composition)
    // first add the scaled track
    let compositionAudioTrack1 = composition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )!
    try! compositionAudioTrack1.insertTimeRange(self.segment2.source, of: self.audioTrack, at: self.segment2.target.start)
    compositionAudioTrack1.scaleTimeRange(
      CMTimeRange(start: self.segment2.target.start, duration: self.segment2.source.duration),
      toDuration: self.segment2.target.duration
    )

    let compositionAudioTrack2 = composition.addMutableTrack(
      withMediaType: .audio, preferredTrackID:
        kCMPersistentTrackID_Invalid
    )!
    try! compositionAudioTrack2.insertTimeRange(self.segment1.source, of: self.audioTrack, at: .zero)
    return composition
  }

  /// Single audio track: OK
  // time:   0s------1s------2s------3s------4s------5s------6s
  // source: |-------[xxxxxxxxxxxxxxx][yyyyyyyyyyyyyy]
  // track:  [xxxxxxxxxxxxxxx][ y y y y y y y   y y y y y y y]
  private var oneAudioTrack: AVComposition {
    let composition = AVMutableComposition()
    self.addVideoTrack(to: composition)
    let compositionAudioTrack = composition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )!
    try! compositionAudioTrack.insertTimeRange(self.segment1.source, of: self.audioTrack, at: .zero)
    try! compositionAudioTrack.insertTimeRange(self.segment2.source, of: self.audioTrack, at: .invalid)
    compositionAudioTrack.scaleTimeRange(
      CMTimeRange(start: self.segment2.target.start, duration: self.segment2.source.duration),
      toDuration: self.segment2.target.duration
    )
    return composition
  }

  /// Single audio track with silence: OK
  // time:   0s------1s------2s------3s------4s------5s------6s
  // source: |-------[xxxxxxxxxxxxxxx][yyyyyyyyyyyyyy]
  // track:  |----------------[ y y y y y y y   y y y y y y y]
  private var oneAudioTrackWithSilence: AVComposition {
    let composition = AVMutableComposition()
    self.addVideoTrack(to: composition)
    let compositionAudioTrack = composition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )!
    try! compositionAudioTrack.insertTimeRange(self.segment2.source, of: self.audioTrack, at: self.segment2.target.start)
    compositionAudioTrack.scaleTimeRange(
      CMTimeRange(start: self.segment2.target.start, duration: self.segment2.source.duration),
      toDuration: self.segment2.target.duration
    )
    return composition
  }
}

// MARK: - Utils

extension ViewController {
  private func addVideoTrack(to composition: AVMutableComposition) {
    let compositionTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )!
    try! compositionTrack.insertTimeRange(self.segment1.source, of: self.videoTrack, at: .zero)
    try! compositionTrack.insertTimeRange(self.segment2.source, of: self.videoTrack, at: .invalid)
    compositionTrack.scaleTimeRange(
      CMTimeRange(start: self.segment2.target.start, duration: self.segment2.source.duration),
      toDuration: self.segment2.target.duration
    )
  }
}

extension CMTime {
  static func seconds(_ value: CMTimeValue, timescale: CMTimeScale = 1) -> Self {
    Self(value: value * CMTimeValue(timescale), timescale: timescale)
  }
}
