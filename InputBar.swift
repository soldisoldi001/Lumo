import SwiftUI
import PhotosUI

struct InputBar: View {
    @Binding var text: String
    var placeholder: String = "Chiedi a Lumo\u{2026}"
    var onSend: () -> Void

    @StateObject private var voice = VoiceInput()
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.card))
            }

            HStack(spacing: 10) {
                TextField("", text: $text,
                          prompt: Text(placeholder).foregroundColor(Color.white.opacity(0.45)))
                    .foregroundColor(.white)
                    .submitLabel(.send)
                    .onSubmit { send() }

                Button(action: toggleMic) {
                    Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(voice.isRecording ? Theme.flame : .white)
                }

                if !text.trimmed.isEmpty {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.violet)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(Capsule().fill(Theme.card))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onChange(of: pickerItem) { item in
            Task { await loadPhoto(item) }
        }
        .onChange(of: voice.transcript) { t in
            if voice.isRecording { text = t }
        }
    }

    private func send() {
        if voice.isRecording { voice.stop() }
        guard !text.trimmed.isEmpty else { return }
        onSend()
    }

    private func toggleMic() {
        if voice.isRecording {
            voice.stop()
            // piccolo ritardo: l'ultima parola può arrivare dopo lo stop
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                if !text.trimmed.isEmpty { onSend() }
            }
        } else {
            voice.start()
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item,
              let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        let t = await OCR.text(from: img)
        await MainActor.run {
            if !t.trimmed.isEmpty {
                text = "Spiegami questo, passo passo:\n" + t
            }
            pickerItem = nil
        }
    }
}
