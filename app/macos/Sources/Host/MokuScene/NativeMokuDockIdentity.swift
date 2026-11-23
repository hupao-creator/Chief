import ChiefCore
import ChiefPluginAPI
import SwiftUI

/// Only the passive mark flips. The editor, its layout seat and native input
/// lifecycle are independent of Thread/Harness identity changes.
struct NativeMokuDockIdentity<Face: View>: View {
    let harness: AnyHarnessPlugin?
    let showsHarness: Bool
    let entranceReady: Bool
    let generation: UUID
    let animation: Animation?
    let onSettled: () -> Void
    @ViewBuilder var face: Face
    @Environment(\.scenePhase) private var scenePhase
    @State private var front: Mark?
    @State private var back: Mark?
    @State private var showingBack = false
    @State private var turning = false
    @State private var snapGeneration = 0
    @State private var transitionGeneration = 0
    @State private var nextMark: Mark?
    @State private var pendingCompletion: (() -> Void)?

    private enum Identity: Equatable { case moku, harness(JSONText?) }
    private struct Mark {
        let identity: Identity
        let harness: AnyHarnessPlugin?
        static var eyes: Self { Self(identity: .moku, harness: nil) }
    }
    private struct Request: Equatable {
        let identity: Identity
        let entranceReady: Bool
        let generation: UUID
        let immediate: Bool
    }
    private var identity: Identity { showsHarness ? .harness(harness?.descriptor.id) : .moku }
    private var destination: Mark? { showingBack ? back : front }
    private var initialMark: Mark {
        showsHarness && entranceReady ? Mark(identity: identity, harness: harness) : .eyes
    }

    var body: some View {
        NativeMokuIdentityFlip(progress: showingBack ? 1 : 0,
            front: artwork(front ?? (back == nil ? initialMark : nil)), back: artwork(back))
            .id(snapGeneration)
            .frame(width: NativeMokuFaceLayout.seat.width, height: NativeMokuFaceLayout.seat.height)
            .onChange(of: Request(identity: identity, entranceReady: entranceReady, generation: generation,
                immediate: animation == nil || scenePhase != .active), initial: true) { _, request in
                update(request)
            }
            .onDisappear {
                transitionGeneration &+= 1
                pendingCompletion = nil
                nextMark = nil
                turning = false
                showingBack = false
                front = nil
                back = nil
            }
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func artwork(_ mark: Mark?) -> some View {
        if let mark {
            Group {
                switch mark.identity {
                case .moku: face
                case .harness:
                    if let logo = mark.harness { logo.logo(size: 24) }
                    else { Image(systemName: "terminal").font(.system(size: 22)) }
                }
            }
            .frame(width: NativeMokuFaceLayout.seat.width, height: NativeMokuFaceLayout.seat.height)
            .transition(.identity)
        }
    }

    private func update(_ request: Request) {
        // A new visit can borrow a flip to the same mark. Only its waiter may
        // admit the editor, and only after the angle has reached its endpoint.
        pendingCompletion = showsHarness && request.entranceReady ? onSettled : nil
        nextMark = nil
        let target = showsHarness && !request.entranceReady ? destination ?? .eyes : initialMark
        if destination == nil || request.immediate {
            transitionGeneration &+= 1
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                // Keep the settled side to avoid remounting the resident face.
                if turning { snapGeneration &+= 1 }
                if showingBack { back = target; front = nil }
                else { front = target; back = nil }
                turning = false
            }
            complete()
        } else if destination?.identity == target.identity {
            if !turning { complete() }
        } else {
            turn(to: target)
        }
    }

    private func turn(to target: Mark) {
        let other = showingBack ? front : back
        if turning && other?.identity != target.identity {
            // Both sides still have visible work. Install a third Harness in
            // the hidden seat only once the current turn has landed.
            nextMark = target
            return
        }
        if showingBack { front = target } else { back = target }
        turning = true
        transitionGeneration &+= 1
        let token = transitionGeneration
        withAnimation(animation, completionCriteria: .removed) {
            showingBack.toggle()
        } completion: {
            guard transitionGeneration == token else { return }
            turning = false
            if let next = nextMark {
                nextMark = nil
                turn(to: next)
            } else {
                if showingBack { front = nil } else { back = nil }
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

private struct NativeMokuIdentityFlip<Front: View, Back: View>: View, @preconcurrency Animatable {
    var progress: CGFloat
    let front: Front
    let back: Back
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        // A reversal retargets this same angle. At the edge neither face has
        // projected pixels. Hidden faces keep an invertible coordinate space.
        let angle = Double(min(1, max(0, progress))) * 180
        ZStack {
            front
                .rotation3DEffect(.degrees(angle < 90 ? -angle : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .opacity(angle < 90 ? 1 : 0)
            back
                .rotation3DEffect(.degrees(angle > 90 ? 180 - angle : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .opacity(angle > 90 ? 1 : 0)
        }
    }
}
