import SwiftUI

struct WatchPhotoDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.dismiss) private var dismiss

    let photos: [MediaItem]
    @State private var currentIndex: Int
    @State private var showControls = true
    @State private var controlsTask: Task<Void, Never>?

    init(photos: [MediaItem], selectedIndex: Int) {
        self.photos = photos
        _currentIndex = State(initialValue: selectedIndex)
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                photoPage(photo)
                    .tag(index)
            }
        }
        .tabViewStyle(.verticalPage)
        .ignoresSafeArea()
        .toolbar(.hidden)
        .persistentSystemOverlays(.hidden)
        .overlay(alignment: .topLeading) {
            if showControls {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showControls, photos.count > 1 {
                Text("\(currentIndex + 1) / \(photos.count)")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showControls)
        .onAppear { scheduleControlsHide() }
        .simultaneousGesture(
            TapGesture().onEnded {
                showControls = true
                scheduleControlsHide()
            }
        )
    }

    private func photoPage(_ photo: MediaItem) -> some View {
        GeometryReader { geo in
            if let url = photoURL(for: photo, size: geo.size) {
                PlexAsyncImage(url: url) {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .aspectRatio(contentMode: .fit)
                .frame(width: geo.size.width, height: geo.size.height)
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func photoURL(for item: MediaItem, size: CGSize) -> URL? {
        guard let imageRepository = try? ImageRepository(context: plexApiContext),
              let path = item.thumbPath else { return nil }
        let width = Int(size.width * 2)
        let height = Int(size.height * 2)
        return imageRepository.transcodeImageURL(path: path, width: width, height: height)
    }

    private func scheduleControlsHide() {
        controlsTask?.cancel()
        controlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            showControls = false
        }
    }
}
