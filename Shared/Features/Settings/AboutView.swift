import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.accentColor)
                    Text("Strimr")
                        .font(.title2.bold())
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("License") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GNU General Public License v3.0")
                        .font(.subheadline.bold())
                    Text("This software is free and open source. You are free to use, modify, and distribute it under the terms of the GPL-3.0 license.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Link(destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!) {
                    Label("View Full License", systemImage: "doc.text")
                }

                Link(destination: URL(string: "https://github.com/jmdurant/strimr")!) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Section("Open Source Libraries") {
                libraryRow(
                    name: "VLCKit",
                    version: "3.7.0",
                    license: "LGPL-2.1+",
                    url: "https://code.videolan.org/videolan/VLCKit",
                    description: "Audio and video playback engine"
                )

                libraryRow(
                    name: "MPVKit",
                    version: "0.41.2",
                    license: "GPL-3.0",
                    url: "https://github.com/nicholaswilde/MPVKit",
                    description: "MPV media player framework"
                )

                libraryRow(
                    name: "libmpv / mpv",
                    version: nil,
                    license: "GPL-2.0+",
                    url: "https://mpv.io",
                    description: "Command-line media player"
                )

                libraryRow(
                    name: "FFmpeg",
                    version: nil,
                    license: "GPL-2.0+ / LGPL-2.1+",
                    url: "https://ffmpeg.org",
                    description: "Multimedia codec and format library"
                )

                libraryRow(
                    name: "Sentry",
                    version: "9.1.0",
                    license: "MIT",
                    url: "https://github.com/getsentry/sentry-cocoa",
                    description: "Error tracking and monitoring"
                )
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This application uses libraries licensed under the LGPL and GPL. In compliance with these licenses, the complete source code is available at the link above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("VLCKit and FFmpeg are provided under the LGPL/GPL. MPV is provided under the GPL-2.0+. These licenses require that derivative works also be made available under compatible open source licenses.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Compliance")
            }
        }
        .navigationTitle("About")
    }

    private func libraryRow(name: String, version: String?, license: String, url: String, description: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    if let version {
                        Text(version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(license)
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }
            .padding(.vertical, 2)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
