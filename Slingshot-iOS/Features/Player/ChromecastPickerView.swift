import SwiftUI

struct ChromecastPickerView: View {
    let renderers: [RendererDevice]
    let activeRendererName: String?
    let onSelect: (String) -> Void
    let onDisconnect: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if renderers.isEmpty {
                    ContentUnavailableView(
                        "No Devices Found",
                        systemImage: "tv.slash",
                        description: Text("Make sure your Chromecast is on the same network.")
                    )
                } else {
                    Section("Available Devices") {
                        ForEach(renderers) { renderer in
                            Button {
                                onSelect(renderer.id)
                            } label: {
                                HStack {
                                    Image(systemName: "tv")
                                        .foregroundStyle(.primary)
                                    Text(renderer.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if activeRendererName == renderer.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }

                    if activeRendererName != nil {
                        Section {
                            Button("Disconnect", role: .destructive) {
                                onDisconnect()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cast to Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onClose() }
                }
            }
        }
    }
}
