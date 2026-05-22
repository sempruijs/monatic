import SwiftUI
import AVFoundation

struct AudioPlayer: View {
    let url: URL
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var speed: Float = 1.0
    @State private var showSpeedPicker = false
    @State private var timer: Timer?

    private static let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

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
                    skipBackward()
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
                    skipForward()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

            Button {
                showSpeedPicker = true
            } label: {
                Text(speedLabel)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSpeedPicker) {
                VStack(spacing: 0) {
                    ForEach(Self.speeds, id: \.self) { s in
                        Button {
                            setSpeed(s)
                            showSpeedPicker = false
                        } label: {
                            HStack {
                                Text(formatSpeed(s))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if s == speed {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .frame(width: 120)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .onKeyPress(.space) {
            togglePlayback()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            skipBackward()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            skipForward()
            return .handled
        }
        .onAppear { loadAudio() }
        .onChange(of: url) { _, _ in loadAudio() }
        .onDisappear { stopAndCleanup() }
    }

    private var speedLabel: String {
        speed == 1.0 ? "1x" : formatSpeed(speed)
    }

    private func loadAudio() {
        stopAndCleanup()
        guard let audioPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        audioPlayer.prepareToPlay()
        audioPlayer.enableRate = true
        audioPlayer.rate = speed
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

    private func skipBackward() {
        player?.currentTime = max((player?.currentTime ?? 0) - 10, 0)
        currentTime = player?.currentTime ?? 0
    }

    private func skipForward() {
        player?.currentTime = min((player?.currentTime ?? 0) + 10, duration)
        currentTime = player?.currentTime ?? 0
    }

    private func setSpeed(_ newSpeed: Float) {
        speed = newSpeed
        player?.rate = newSpeed
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

    private func formatSpeed(_ s: Float) -> String {
        s.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fx", s)
            : String(format: "%.2gx", s)
    }
}
