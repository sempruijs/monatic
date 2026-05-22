import SwiftUI
import AVFoundation

struct AudioPlayer: View {
    let url: URL
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(url.lastPathComponent)
                .font(.title3)
                .lineLimit(1)

            VStack(spacing: 8) {
                Slider(
                    value: $currentTime,
                    in: 0...max(duration, 1),
                    onEditingChanged: { editing in
                        if !editing {
                            player?.currentTime = currentTime
                        }
                    }
                )
                .frame(maxWidth: 400)

                HStack {
                    Text(formatTime(currentTime))
                        .monospacedDigit()
                    Spacer()
                    Text(formatTime(duration))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            }

            HStack(spacing: 24) {
                Button {
                    player?.currentTime = max((player?.currentTime ?? 0) - 10, 0)
                    currentTime = player?.currentTime ?? 0
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                }
                .buttonStyle(.plain)

                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .buttonStyle(.plain)

                Button {
                    player?.currentTime = min((player?.currentTime ?? 0) + 10, duration)
                    currentTime = player?.currentTime ?? 0
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadAudio() }
        .onChange(of: url) { _, _ in loadAudio() }
        .onDisappear { stopAndCleanup() }
    }

    private func loadAudio() {
        stopAndCleanup()
        guard let audioPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        audioPlayer.prepareToPlay()
        player = audioPlayer
        duration = audioPlayer.duration
        currentTime = 0
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
            timer = nil
        } else {
            player.play()
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                currentTime = player.currentTime
                if !player.isPlaying {
                    isPlaying = false
                    timer?.invalidate()
                    timer = nil
                }
            }
        }
    }

    private func stopAndCleanup() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        isPlaying = false
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
