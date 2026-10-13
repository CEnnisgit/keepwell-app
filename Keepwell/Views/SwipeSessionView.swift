import SwiftUI

struct SwipeSessionView: View {
    let session: ReviewSession
    @Environment(PhotoLibrary.self) private var library
    @Environment(CleanupStore.self) private var cleanup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Decision { case keep, delete }
    @State private var queue: [String] = []
    @State private var index = 0
    @State private var history: [(id: String, decision: Decision)] = []
    @State private var gesture = CardGestureState()
    @State private var flyOff: CGFloat = 0
    @State private var prepared = false

    private var current: String? { index < queue.count ? queue[index] : nil }
    private var allIDs: [String] { library.ids(for: session) }
    private var drag: CGSize { gesture.swipe }
    /// Keep and Delete are off while there is no card or the card is zoomed; the round button style dims them.
    private var decideDisabled: Bool { current == nil || !gesture.canDecide }
    /// Month sessions walk the whole month and skip what was already swiped, so the header reads
    /// "121 of 340" and the month resumes at its first unreviewed photo.
    private var monthID: String? {
        if case .month(let id) = session { return id }
        return nil
    }
    private var springOrNone: Animation? { reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8) }

    var body: some View {
        VStack(spacing: 16) {
            header
            ZStack {
                if let current {
                    if nextIndex(after: index) < queue.count {
                        card(for: queue[nextIndex(after: index)]).scaleEffect(0.95).opacity(0.6).allowsHitTesting(false)
                    }
                    card(for: current, isTop: true)
                        .offset(x: drag.width + flyOff, y: drag.height * 0.2)
                        .rotationEffect(.degrees(rotation))
                        .gesture(dragGesture)
                        .simultaneousGesture(pinchGesture)
                        .onTapGesture(count: 2) { toggleZoom() }
                        .accessibilityAction(named: Text(gesture.isZoomed ? "Zoom out" : "Zoom in")) { toggleZoom() }
                        .id(current)
                        .transition(.opacity)
                } else if prepared {
                    doneView
                }
            }
            .frame(maxHeight: .infinity)
            controls
        }
        .padding(.horizontal, KWLayout.screenPadding)
        .padding(.bottom, 12)
        .background(Color.kwBackground.ignoresSafeArea())
        .navigationTitle(library.title(for: session))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.tray) {
                    Label("Review (\(cleanup.pending.count))", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(cleanup.pending.isEmpty)
            }
        }
        .onAppear(perform: prepare)
        .onChange(of: current) { old, _ in if old != nil { gesture.reset() } }
    }

    private func prepare() {
        guard !prepared else { return }
        if let monthID, let month = library.month(monthID) {
            queue = month.assetIDs
            index = cleanup.monthProgress.resumeIndex(in: month)
        } else {
            queue = allIDs.filter { !cleanup.kept.contains($0) && !cleanup.isPending($0) }
            index = 0
        }
        prepared = true
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "KWScreen") {
        case "swipe":
            // Screenshot hook: hold the top card mid-swipe so the Keep stamp and rotation are visible.
            gesture.debugHoldSwipe(CGSize(width: 84, height: -12))
        case "zoom", "zoomdim":
            // Screenshot hooks: the top card double-tapped to 2.5x, which also requests the detail image.
            // `zoomdim` captures the same state to show the dimmed Keep and Delete buttons below the card.
            gesture.doubleTap()
            KWDebugState.set(["zoomScale": Double(gesture.scale), "zoomBlocksDecide": !gesture.canDecide,
                              "keepDeleteDimmed": decideDisabled, "zoomCurrent": current ?? ""])
        default:
            break
        }
        #endif
    }

    /// Next position to show after `position`: the following unswiped photo in a month, else simply the next one.
    private func nextIndex(after position: Int) -> Int {
        guard let monthID else { return position + 1 }
        return cleanup.monthProgress.nextUnreviewed(in: monthID, ids: queue, from: position + 1)
    }

    private var rotation: Double {
        let r = Double((drag.width + flyOff) / 20)
        return max(-12, min(12, r))
    }

    private var header: some View {
        HStack {
            Text(queue.isEmpty ? "" : "\(min(index + 1, queue.count)) of \(queue.count)")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.kwTextSecondary)
            Spacer()
            Text(gesture.isZoomed ? "Pinch or double-tap to zoom out" : "← Delete · Keep →")
                .font(.footnote)
                .foregroundStyle(Color.kwTextSecondary)
        }
        .padding(.top, 8)
    }

    private func card(for id: String, isTop: Bool = false) -> some View {
        let info = library.byID[id]
        let zoom = isTop ? gesture.scale : 1
        let pan = isTop ? gesture.offset : .zero
        return GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Color.kwSurface
                Color.black.opacity(0.9)
                AssetImage(id: id, targetSize: geo.size, contentMode: .fit,
                           wantsDetail: isTop && gesture.wantsHighResolution)
                    .scaleEffect(zoom)
                    .offset(pan)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .opacity(zoom > 1.01 ? 0 : 1)
                    .allowsHitTesting(false)
                if isTop && zoom > 1.01 {
                    Text("\(Double(zoom), format: .number.precision(.fractionLength(1)))×")
                        .font(.footnote.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(16)
                        .accessibilityLabel("Zoomed \(Double(zoom), format: .number.precision(.fractionLength(1))) times")
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let date = info?.date {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline.weight(.semibold))
                    }
                    if let info, info.isVideo {
                        Label(Duration.seconds(info.duration).formatted(.time(pattern: .minuteSecond)),
                              systemImage: "video.fill").font(.footnote)
                    }
                }
                .foregroundStyle(.white)
                .padding(16)
                .opacity(zoom > 1.01 ? 0 : 1)
                stamps(for: id)
            }
            .clipShape(RoundedRectangle(cornerRadius: KWRadius.card, style: .continuous))
            .contentShape(Rectangle())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            .onAppear { if isTop { gesture.container = geo.size } }
            .onChange(of: geo.size) { _, size in if isTop { gesture.container = size } }
        }
    }

    @ViewBuilder
    private func stamps(for id: String) -> some View {
        if id == current {
            let progress = (drag.width + flyOff) / 120
            ZStack {
                stamp("KEEP", color: .kwKeep).rotationEffect(.degrees(-12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .opacity(Double(max(0, min(1, progress))))
                stamp("DELETE", color: .kwDelete).rotationEffect(.degrees(12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .opacity(Double(max(0, min(1, -progress))))
            }
            .padding(24)
            .allowsHitTesting(false)
        }
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(.title, design: .rounded).weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: KWRadius.badge, style: .continuous).stroke(color, lineWidth: 4))
            .background(Color.kwSurface.opacity(0.85), in: RoundedRectangle(cornerRadius: KWRadius.badge, style: .continuous))
    }

    /// One finger: swipes at 1x, pans when zoomed. A drag that began zoomed or met a pinch never commits.
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { gesture.dragChanged($0.translation) }
            .onEnded { value in
                let commit = gesture.dragEnded(translation: value.translation, predictedEnd: value.predictedEndTranslation)
                switch commit {
                case .keep: decide(.keep)
                case .delete: decide(.delete)
                case nil: withAnimation(springOrNone) { gesture.cancelSwipe() }
                }
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { gesture.pinchChanged($0.magnification) }
            .onEnded { _ in withAnimation(springOrNone) { gesture.pinchEnded() } }
    }

    private func toggleZoom() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { gesture.doubleTap() }
    }

    private func decide(_ decision: Decision) {
        guard let id = current, gesture.canDecide else { return }
        switch decision {
        case .keep: cleanup.keep(id)
        case .delete: cleanup.markForDeletion(id)
        }
        if let month = monthID ?? library.monthByID[id] {
            cleanup.recordReviewed(id, inMonth: month)
        }
        history.append((id, decision))
        let next = nextIndex(after: index)
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) {
                gesture.reset()
                index = next
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                flyOff = decision == .keep ? 600 : -600
            } completion: {
                gesture.reset()
                flyOff = 0
                index = next
            }
        }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        cleanup.clearDecision(last.id)
        if let month = monthID ?? library.monthByID[last.id] {
            cleanup.clearReviewed(last.id, inMonth: month)
        }
        if let pos = queue.firstIndex(of: last.id) {
            withAnimation(springOrNone) {
                index = pos
                gesture.reset()
                flyOff = 0
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            roundButton("xmark", color: .kwDelete, label: "Mark for deletion", hint: zoomHint) { decide(.delete) }
                .disabled(decideDisabled)
            roundButton("arrow.uturn.backward", color: .kwTextSecondary, label: "Undo", small: true) { undo() }
                .disabled(history.isEmpty)
            roundButton("heart.fill", color: .kwKeep, label: "Keep", hint: zoomHint) { decide(.keep) }
                .disabled(decideDisabled)
        }
    }

    private var zoomHint: String { gesture.isZoomed ? "Zoom out to decide" : "" }

    private func roundButton(_ icon: String, color: Color, label: String, small: Bool = false, hint: String = "",
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: small ? 20 : 26, weight: .bold))
                .foregroundStyle(color)
        }
        .buttonStyle(RoundButtonStyle(diameter: small ? 52 : 68))
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56)).foregroundStyle(Color.kwBrandTeal)
            Text(allIDs.isEmpty ? "Nothing here" : "All reviewed")
                .font(.title.weight(.bold))
            Text(cleanup.pending.isEmpty
                 ? "Nothing is marked for deletion."
                 : "\(cleanup.pending.count) items are waiting in your review tray.")
                .foregroundStyle(Color.kwTextSecondary)
                .multilineTextAlignment(.center)
            if !cleanup.pending.isEmpty {
                NavigationLink("Review and delete", value: Route.tray)
                    .buttonStyle(PrimaryButtonStyle())
            }
            if let monthID, let month = library.month(monthID) {
                Button("Review again") {
                    cleanup.resetMonth(month)
                    prepared = false
                    history = []
                    prepare()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.kwBrandTealText)
            } else if !allIDs.isEmpty {
                Button("Start this session over") {
                    cleanup.resetKept(for: allIDs)
                    prepared = false
                    history = []
                    prepare()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.kwBrandTealText)
            }
        }
        .padding()
    }
}

/// Circular control for the swipe screen. Reads `isEnabled`, so any disabled round button (Keep and Delete
/// while zoomed, Undo with nothing to undo) dims the same way; VoiceOver reads it as dimmed via `.disabled`.
private struct RoundButtonStyle: ButtonStyle {
    let diameter: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        RoundButtonBody(configuration: configuration, diameter: diameter)
    }

    private struct RoundButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let diameter: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .frame(width: diameter, height: diameter)
                .background(Color.kwSurface, in: Circle())
                .shadow(color: .black.opacity(isEnabled ? 0.08 : 0), radius: 6, y: 3)
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isEnabled)
        }
    }
}
