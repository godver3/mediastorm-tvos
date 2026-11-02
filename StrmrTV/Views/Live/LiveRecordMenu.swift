import SwiftUI

/// The long-press recording actions on a guide programme that hasn't ended (Expo's TV
/// programme menu): Stop / Cancel the recording that covers it, else Record (on now) or
/// Record Once (later); then Record Series, every airing of the title on this channel.
struct LiveProgramRecordMenu: View {
    let channel: LiveChannel
    let program: EPGProgram
    @EnvironmentObject private var store: LiveStore

    var body: some View {
        if let recording = store.recording(on: channel, during: program) {
            Button(role: .destructive) {
                store.cancel(recording)
            } label: {
                Label(recording.status == .pending ? "Cancel Scheduled Recording" : "Stop Recording",
                      systemImage: "stop.circle")
            }
        } else {
            Button {
                store.record(program, on: channel)
            } label: {
                Label(program.isAiring(at: Date()) ? "Record" : "Record Once", systemImage: "record.circle")
            }
        }
        Button {
            store.recordSeries(program, on: channel)
        } label: {
            Label("Record Series", systemImage: "repeat.circle")
        }
    }
}

/// The channel's recording actions (Expo's TV channel menu): record what is on now (or stop
/// it), every airing of it, or the next two hours. `airing` is false on a guide programme
/// cell, whose own menu already offers the programme's.
struct LiveChannelRecordMenu: View {
    let channel: LiveChannel
    var airing = true
    @EnvironmentObject private var store: LiveStore

    var body: some View {
        if airing, let current = store.current(channel) {
            if let recording = store.recording(on: channel, during: current) {
                Button(role: .destructive) {
                    store.cancel(recording)
                } label: {
                    Label("Stop Recording", systemImage: "stop.circle")
                }
            } else {
                Button {
                    store.record(current, on: channel)
                } label: {
                    Label("Record Current Program", systemImage: "record.circle")
                }
            }
            Button {
                store.recordSeries(current, on: channel)
            } label: {
                Label("Record Every Airing", systemImage: "repeat.circle")
            }
        }
        Button {
            store.recordTwoHours(channel)
        } label: {
            Label("Record 2 Hour Block", systemImage: "clock.badge")
        }
    }
}

/// A guide cell's or channel card's mark: a red dot while recording, a clock when scheduled.
struct LiveRecordingBadge: View {
    let recording: Recording

    var body: some View {
        Image(systemName: recording.status == .running ? "record.circle.fill" : "clock")
            .font(.caption2.weight(.bold))
            .foregroundStyle(recording.status == .running ? Color.red : Color.accentColor)
            .accessibilityLabel(recording.status.label)
    }
}
