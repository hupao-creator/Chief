import ChiefCore
import ChiefPluginAPI
import ChiefPluginUI
import SwiftUI

/// Only the passive mark flips. The editor, its layout seat and native input
/// lifecycle are independent of Thread/Harness identity changes.
struct NativeMokuDockIdentity<Face: View>: View {
    let harness: AnyHarnessPlugin?
    let showsHarness: Bool
    let entranceReady: Bool
    let generation: UUID
    let motion: Bool
    let offset: CGPoint
    let readingPlane: CGSize?
    let readingMotion: NativeMokuReadingMorph?
    let onSettled: () -> Void
    @ViewBuilder var face: Face
    @Environment(\.scenePhase) private var scenePhase
    @State private var displayedIdentity: Identity?
    @State private var displayedHarness: AnyHarnessPlugin?
    @State private var settledIdentity: Identity?
    @State private var transitionGeneration = 0
    @State private var pendingCompletion: (() -> Void)?

    private enum Identity: Hashable { case moku, harness(JSONText?) }
    private struct Request: Equatable {
        let identity: Identity
        let entranceReady: Bool
        let generation: UUID
        let immediate: Bool
    }
    private var identity: Identity { showsHarness ? .harness(harness?.descriptor.id) : .moku }
    private var transition: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: NativeMokuIdentityFlip(progress: 0, incoming: true),
                identity: NativeMokuIdentityFlip(progress: 1, incoming: true)),
            removal: .modifier(active: NativeMokuIdentityFlip(progress: 0, incoming: false),
                identity: NativeMokuIdentityFlip(progress: 1, incoming: false)))
    }

    private var mark: some View {
        let displayed = displayedIdentity ?? (showsHarness && !entranceReady ? .moku : identity)
        let logo = displayedIdentity == nil ? harness : displayedHarness
        return ZStack {
            if case .harness = displayed {
                Group {
                    if let logo { logo.logo(size: 24) }
                    else { Image(systemName: "terminal").font(.system(size: 22)) }
                }
                .frame(width: NativeMokuFaceLayout.seat.width, height: NativeMokuFaceLayout.seat.height)
                .id(displayed)
                .transition(transition)
            } else {
                face.transition(transition)
            }
        }
        .frame(width: NativeMokuFaceLayout.seat.width, height: NativeMokuFaceLayout.seat.height)
    }

    var body: some View {
        Group {
            if let readingPlane {
                NativeMokuIdentityPosition(plane: readingPlane, offset: offset, motion: readingMotion) { mark }
                    .frame(width: readingPlane.width, height: readingPlane.height)
            } else {
                mark.offset(x: offset.x, y: offset.y)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: NativeMokuCapsuleLayout.cornerRadius))
            }
        }
        .onChange(of: Request(identity: identity, entranceReady: entranceReady, generation: generation,
            immediate: !motion || scenePhase != .active), initial: true) { _, request in
            update(request)
        }
        .onDisappear {
            transitionGeneration &+= 1
            pendingCompletion = nil
            displayedIdentity = nil; settledIdentity = nil
            displayedHarness = nil
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func update(_ request: Request) {
        // A new composer can borrow an in-flight flip to the same mark. Replace
        // its waiter, but never treat the target value as animation completion.
        pendingCompletion = showsHarness && request.entranceReady ? onSettled : nil
        // Travel keeps the current mark. In particular a continuation between
        // Agent visits must not turn a retained Harness logo back into eyes.
        let target = showsHarness && !request.entranceReady ? displayedIdentity ?? .moku : request.identity
        if displayedIdentity == nil || request.immediate {
            transitionGeneration &+= 1
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedIdentity = target
                if target == request.identity { displayedHarness = harness }
                settledIdentity = target
            }
            complete()
        } else if displayedIdentity == target {
            if settledIdentity == target { complete() }
        } else {
            transitionGeneration &+= 1
            let token = transitionGeneration
            settledIdentity = nil
            withAnimation(NativeReadingPageTiming.openingAnimation, completionCriteria: .removed) {
                displayedIdentity = target
                displayedHarness = harness
            } completion: {
                guard transitionGeneration == token else { return }
                settledIdentity = target
                complete()
            }
        }
    }

    private func complete() {
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?()
    }
}

private struct NativeMokuIdentityFlip: ViewModifier, @preconcurrency Animatable {
    var progress: CGFloat
    let incoming: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        // Retire the front in the first half, then reveal the back. Both rotate
        // downward about the same horizontal axis, with no mirrored back face.
        let visible = min(1, max(0, progress * 2 - 1))
        // A fully hidden face has no projected pixels. Keep its coordinate
        // space invertible for SwiftUI geometry and accessibility queries.
        let degrees = visible > 0 ? (incoming ? 90 : -90) * (1 - visible) : 0
        content
            .rotation3DEffect(.degrees(Double(degrees)),
                axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .opacity(visible > 0 ? 1 : 0)
    }
}
