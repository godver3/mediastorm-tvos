import AetherEngine
import Foundation

extension LivePlayerViewController {
    /// Every tune joins with `.fastZap`, a few seconds behind the edge. A source that pauses and
    /// then bursts (an IPTV line holding back 3 to 5 s, then handing over several segments) can
    /// leave the playlist unchanged past AVPlayer's patience (-12888) or run the buffer dry; the
    /// player rides that out in place, as ExoPlayer does on Android TV, rather than retuning. A
    /// retune opened a new provider connection, dropped whatever was buffered and sat on black
    /// for the standard join's 18 s holdback, often just as the next burst arrived. Real
    /// failures (a source reset, the stream ending, an engine error) still retune or fail.
    func makeLoadOptions(remoteHLS: Bool) -> LoadOptions {
        var options = baseLoadOptions()
        options.isLive = true
        options.liveJoinProfile = .fastZap
        // The server's HLS session goes straight to AVPlayer; a direct stream is demuxed.
        options.nativeRemoteHLS = remoteHLS
        if !remoteHLS {
            // The engine's 50 MiB probe is sized for VOD files with sparse tracks. A live TS read
            // arrives in real time: a 4K channel at ~15 Mbps spent 24 s of open_input reading
            // 45 MB of it and missed the 25 s first-frame deadline. 8 MiB is a few seconds of
            // such a channel, still the PMT and several keyframes.
            options.probesize = Self.liveDirectProbeBytes
            options.liveEdgeCushionSeconds = Self.liveDirectCushionSeconds
            options.dvrWindowSeconds = timeshiftWindow
        }
        return options
    }

    static let liveDirectProbeBytes: Int64 = 8 << 20

    /// Broadcast muxers (an HDHomeRun's ATSC feed) send each AC-3 frame up to ~0.8 s after the video
    /// of the same timestamp. At the bare edge the software clock starts on the first keyframe, so
    /// every audio frame reached the renderer already late: aLead sat at -0.2 to -0.8 s, the
    /// renderer never had enough data and the sound cut out a few seconds in while the picture
    /// played on. Joining 2 s back keeps the audio ~1.2 s ahead for ~1 s of extra tune time.
    static let liveDirectCushionSeconds: Double = 2
}
