import AetherEngine
import Combine
import UIKit

/// The Stream tab (`StreamInfoViewController`) beside AVKit's Info tab. The file and source are
/// fixed for the session; the video and audio lines follow the engine, which publishes them as
/// the probe (or, on the native HLS bypass, AVPlayer's item) reveals them and on audio switches.
extension EnginePlayerViewController {
    func installStreamInfo(file: String?, source: String?) {
        streamInfoBase = StreamInfo(file: file, source: source)
        customInfoViewControllers = [streamInfoTab]
        refreshStreamInfo()
        let changes: [AnyPublisher<Void, Never>] = [
            engine.$sourceVideoWidth.map { _ in () }.eraseToAnyPublisher(),
            engine.$sourceVideoHeight.map { _ in () }.eraseToAnyPublisher(),
            engine.$sourceVideoCodecName.map { _ in () }.eraseToAnyPublisher(),
            engine.$sourceVideoStreamFormat.map { _ in () }.eraseToAnyPublisher(),
            engine.$sourceVideoFrameRate.map { _ in () }.eraseToAnyPublisher(),
            engine.$sourceVideoBitrate.map { _ in () }.eraseToAnyPublisher(),
            engine.$sourceVideoFormat.map { _ in () }.eraseToAnyPublisher(),
            engine.$videoFormat.map { _ in () }.eraseToAnyPublisher(),
            engine.$sourceDVProfile.map { _ in () }.eraseToAnyPublisher(),
            engine.$audioTracks.map { _ in () }.eraseToAnyPublisher(),
            engine.$activeAudioTrackIndex.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.refreshStreamInfo() }
            .store(in: &cancellables)
    }

    private func refreshStreamInfo() {
        let info = Self.streamInfo(base: streamInfoBase, engine: engine)
        streamInfoTab.update(info)
        streamInfoDidChange(info)
    }

    static func streamInfo(base: StreamInfo, engine: AetherEngine) -> StreamInfo {
        var info = base
        let hasVideo = engine.sourceVideoWidth > 0 || engine.sourceVideoCodecName != nil
        info.video = StreamFormat.video(
            width: Int(engine.sourceVideoWidth), height: Int(engine.sourceVideoHeight),
            codec: engine.sourceVideoCodecName, profile: engine.sourceVideoStreamFormat?.profile,
            frameRate: engine.sourceVideoFrameRate, bitrate: engine.sourceVideoBitrate)
        info.dynamicRange = hasVideo
            ? StreamFormat.dynamicRange(source: engine.sourceVideoFormat, dvProfile: engine.sourceDVProfile,
                                        displayed: engine.videoFormat)
            : nil
        let active = engine.activeAudioTrackIndex
        let audio = engine.audioTracks.first { $0.id == active }
        info.audio = StreamFormat.audio(audio)
        info.summary = StreamSource.joined([
            StreamFormat.compactVideo(height: Int(engine.sourceVideoHeight), codec: engine.sourceVideoCodecName),
            hasVideo ? StreamFormat.formatName(engine.sourceVideoFormat, dvProfile: engine.sourceDVProfile) : nil,
            StreamFormat.compactAudio(audio), base.source,
        ])
        return info
    }
}
