import SwiftUI

private let gridBackground: Color = {
    #if os(watchOS) || os(tvOS)
    return Color.black
    #else
    return Color(.systemBackground)
    #endif
}()

struct EPGGridView: View {
    var viewModel: LiveTVViewModel
    var onTune: (PlexChannel) -> Void
    var onRecord: ((EPGGridProgram, PlexChannel) -> Void)?

    #if os(tvOS)
    private let channelColumnWidth: CGFloat = 200
    private let rowHeight: CGFloat = 80
    private let pixelsPerMinute: CGFloat = 5
    private let headerHeight: CGFloat = 50
    private let channelFont: Font = .headline
    private let channelNumberFont: Font = .subheadline
    private let programFont: Font = .callout
    #else
    private let channelColumnWidth: CGFloat = 120
    private let rowHeight: CGFloat = 56
    private let pixelsPerMinute: CGFloat = 3.5
    private let headerHeight: CGFloat = 32
    private let channelFont: Font = .caption
    private let channelNumberFont: Font = .caption2
    private let programFont: Font = .caption2
    #endif

    private let blockGap: CGFloat = 2

    private var windowStart: Date {
        viewModel.epgTimeWindow?.start ?? Date()
    }

    private var windowEnd: Date {
        viewModel.epgTimeWindow?.end ?? Date()
    }

    private var totalGridWidth: CGFloat {
        let totalMinutes = windowEnd.timeIntervalSince(windowStart) / 60
        return CGFloat(totalMinutes) * pixelsPerMinute
    }

    private var timeSlots: [Date] {
        guard viewModel.epgTimeWindow != nil else { return [] }
        var slots: [Date] = []
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: windowStart)
        let roundedMinute = (comps.minute ?? 0) / 30 * 30
        var slot = calendar.date(bySettingHour: comps.hour ?? 0, minute: roundedMinute, second: 0, of: windowStart) ?? windowStart
        while slot <= windowEnd {
            slots.append(slot)
            slot = slot.addingTimeInterval(30 * 60)
        }
        return slots
    }

    private func minutesToPoints(_ minutes: Double) -> CGFloat {
        CGFloat(minutes) * pixelsPerMinute
    }

    var body: some View {
        Group {
            if viewModel.isLoadingGrid, viewModel.epgRows.isEmpty {
                ProgressView("Loading guide...")
            } else if viewModel.epgRows.isEmpty {
                ContentUnavailableView(
                    "No Guide Data",
                    systemImage: "tv",
                    description: Text("EPG data is not available.")
                )
            } else {
                gridContent
            }
        }
        .task {
            await viewModel.loadEPGGrid()
        }
    }

    // MARK: - Grid Layout

    private var gridContent: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                channelColumn
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        timeHeader
                        programRows
                    }
                    .frame(width: totalGridWidth)
                }
            }
        }
    }

    // MARK: - Channel Column

    private var channelColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(width: channelColumnWidth, height: headerHeight)

            ForEach(viewModel.epgRows) { row in
                HStack(spacing: 6) {
                    Text(row.channel.channelNumber)
                        .font(channelNumberFont)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)

                    Text(row.channel.displayName)
                        .font(channelFont)
                        .lineLimit(1)
                }
                .frame(width: channelColumnWidth, height: rowHeight, alignment: .leading)
                .padding(.leading, 8)
                .background(gridBackground.opacity(0.95))
            }
        }
        .background(gridBackground)
    }

    // MARK: - Time Header

    private var timeHeader: some View {
        ZStack(alignment: .leading) {
            ForEach(timeSlots, id: \.self) { slot in
                let x = minutesToPoints(slot.timeIntervalSince(windowStart) / 60)
                Text(slot, format: .dateTime.hour().minute())
                    .font(channelNumberFont)
                    .foregroundStyle(.secondary)
                    .offset(x: x)
            }
        }
        .frame(width: totalGridWidth, height: headerHeight, alignment: .leading)
        .background(gridBackground.opacity(0.95))
    }

    // MARK: - Program Rows (HStack-based, no ZStack/offset)

    private var programRows: some View {
        ForEach(viewModel.epgRows) { row in
            programRow(row: row)
                .frame(width: totalGridWidth, height: rowHeight)
                .background(Color.gray.opacity(0.06))
                .overlay(alignment: .leading) { nowLine }
                .clipped()
        }
    }

    /// Build an HStack of gap-spacers and program blocks for one channel row.
    private func programRow(row: EPGGridRow) -> some View {
        HStack(spacing: 0) {
            let programs = row.programs
            ForEach(Array(programs.enumerated()), id: \.element.id) { index, program in
                let clampedStart = max(program.beginsAt, windowStart)
                let clampedEnd = min(program.endsAt, windowEnd)

                // Gap before this block
                let prevEnd: Date = index == 0 ? windowStart : max(programs[index - 1].endsAt, windowStart)
                let gapMinutes = clampedStart.timeIntervalSince(prevEnd) / 60
                let gapWidth = minutesToPoints(gapMinutes)
                if gapWidth > 0 {
                    Color.clear.frame(width: gapWidth)
                }

                // Program block
                let blockMinutes = clampedEnd.timeIntervalSince(clampedStart) / 60
                let blockWidth = minutesToPoints(blockMinutes) - blockGap
                let now = Date()
                let isAiring = program.beginsAt <= now && program.endsAt >= now
                let bgColor: Color = isAiring
                    ? .blue.opacity(0.3)
                    : (index.isMultiple(of: 2) ? .gray.opacity(0.22) : .gray.opacity(0.14))
                let borderColor: Color = isAiring ? .blue.opacity(0.6) : .gray.opacity(0.35)

                Button {
                    if isAiring {
                        onTune(row.channel)
                    } else {
                        onRecord?(program, row.channel)
                    }
                } label: {
                    Text(program.title)
                        .font(programFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .frame(width: max(blockWidth, 0), height: rowHeight - 8)
                .background(RoundedRectangle(cornerRadius: 4).fill(bgColor))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(borderColor, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Now Indicator

    private var nowLine: some View {
        let x = minutesToPoints(Date().timeIntervalSince(windowStart) / 60)
        return Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: rowHeight)
            .offset(x: x)
    }
}
