//
//  DraggableZoomable.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/6/22.
//  Originally from Stack Overflow: https://stackoverflow.com/questions/58341820/isnt-there-an-easy-way-to-pinch-to-zoom-in-an-image-in-swiftui

import SwiftUI

struct DraggableAndZoomableView: ViewModifier {
    @GestureState private var scaleState: CGFloat = 1
    @GestureState private var offsetState = CGSize.zero
    @GestureState private var didScaleState = false
    @GestureState private var rotationState = Angle.zero
    
    @State private var offset = CGSize.zero
    @State private var scale: CGFloat = 1
    @State private var rotation = Angle.zero
    @State private var animating = false
    
    @State private var quicklookURL: URL? = nil
    
    func resetStatus() {
        offset = CGSize.zero
        scale = 1
        rotation = Angle.zero
    }
    
    init() {
        resetStatus()
    }
    
    var unlocked: Bool {
        return true
    }
    
    var isScaled: Bool {
        return scale != 1 || scaleState != 1 || animating
    }
    
    var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($scaleState) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .updating($didScaleState) { currentState, gestureState, _ in
                gestureState = gestureState || currentState != 1.0
            }
            .onEnded { value in
                scale *= value
                if scale < 1 {
                    withAnimation(.interactiveSpring()) {
                        scale = 1
                    }
                }
            }
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .updating($offsetState) { currentState, gestureState, _ in
                if unlocked {
                    gestureState = currentState.translation
                }
            }.onEnded { value in
                if unlocked {
                    offset.height += value.translation.height
                    offset.width += value.translation.width
                }
            }
    }
    
    var rotateGesture: some Gesture {
        RotationGesture()
            .updating($rotationState) { currentState, rotationState, _ in
                if (unlocked) {
                    rotationState = currentState
                }
            }.onEnded {
                rotation += $0
                withAnimation(.interactiveSpring()) {
                    rotation = Angle.zero
                }
            }
    }
    
    var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded { _ in
            animating = true
            withAnimation {
                if isScaled {
                    resetStatus()
                } else {
                    scale = 2
                }
            }
        }
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale * scaleState)
            .rotationEffect(rotation + rotationState)
            .offset(x: offset.width + offsetState.width, y: offset.height + offsetState.height)
            .zIndex(isScaled ? 1 : 0)
            .gesture(rotateGesture.simultaneously(with: zoomGesture).simultaneously(with: dragGesture))
            .gesture(doubleTapGesture)
            .onAnimationCompleted(for: scale) {
                animating = false
            }
    }
}

/// An animatable modifier that is used for observing animations for a given animatable value.
struct AnimationCompletionObserverModifier<Value>: AnimatableModifier where Value: VectorArithmetic {

    /// While animating, SwiftUI changes the old input value to the new target value using this property. This value is set to the old value until the animation completes.
    var animatableData: Value {
        didSet {
            notifyCompletionIfFinished()
        }
    }

    /// The target value for which we're observing. This value is directly set once the animation starts. During animation, `animatableData` will hold the oldValue and is only updated to the target value once the animation completes.
    private var targetValue: Value

    /// The completion callback which is called once the animation completes.
    private var completion: () -> Void

    init(observedValue: Value, completion: @escaping () -> Void) {
        self.completion = completion
        self.animatableData = observedValue
        targetValue = observedValue
    }

    /// Verifies whether the current animation is finished and calls the completion callback if true.
    private func notifyCompletionIfFinished() {
        guard animatableData == targetValue else { return }

        /// Dispatching is needed to take the next runloop for the completion callback.
        /// This prevents errors like "Modifying state during view update, this will cause undefined behavior."
        DispatchQueue.main.async {
            self.completion()
        }
    }

    func body(content: Content) -> some View {
        /// We're not really modifying the view so we can directly return the original input value.
        return content
    }
}


// Wrap `draggable()` in a View extension to have a clean call site
extension View {
    func draggableAndZoomable() -> some View {
        return modifier(DraggableAndZoomableView())
    }
}


extension View {
    /// Calls the completion handler whenever an animation on the given value completes.
    /// - Parameters:
    ///   - value: The value to observe for animations.
    ///   - completion: The completion callback to call once the animation completes.
    /// - Returns: A modified `View` instance with the observer attached.
    func onAnimationCompleted<Value: VectorArithmetic>(for value: Value, completion: @escaping () -> Void) -> ModifiedContent<Self, AnimationCompletionObserverModifier<Value>> {
        return modifier(AnimationCompletionObserverModifier(observedValue: value, completion: completion))
    }
}

