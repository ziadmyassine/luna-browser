//
//  AgentRoverView+Moods.swift
//  Luna
//
//  What Astro does in each mood. Waiting, it breathes, blinks, and now and
//  then looks about. Ready for a first task, it floats higher, looks down
//  at the field and about, says hello with a tilt and a glint, and blinks
//  twice now and then. Thinking, it tilts its head, its eyes wander up and a
//  thought bubble fills dot by dot. Working, it bobs with its ears lit and a
//  light sweeps its visor. Writing, its eyes run along a line and back and
//  its head keeps a typing beat. Asking for the user, it rocks and its ears flash.
//  Done, it hops, smiles and sparkles; gone wrong, it sinks and dims;
//  stopped, it dozes. Whatever the mood, it never holds quite still: it
//  breathes, and blinks whenever its eyes are open.
//
//  Every loop is a Core Animation one, so it costs nothing between frames,
//  and the few that happen now and then (a blink, a glance) run on timers
//  that stop when the view leaves its window. Under Reduce Motion only the
//  face changes.
//

import AppKit

extension AgentRoverView {

    func applyMood() {
        stopTimers()
        for layer in [figure, head, ground, eyes, scan, leftEye, rightEye] + earLights + thoughts + sparkles {
            layer.removeAllAnimations()
        }
        setEyes(mood)
        visor.opacity = mood == .stopped || mood == .sad ? 0.75 : 1
        for light in earLights { light.opacity = [.ready, .thinking, .working, .writing, .waving].contains(mood) ? 1 : 0 }
        for dot in thoughts { dot.opacity = 0 }
        for star in sparkles { star.opacity = 0 }
        scan.opacity = 0
        guard !Tokens.Motion.reduceMotion, window != nil else { return }
        animate(mood)
    }

    private func animate(_ mood: Mood) {
        switch mood {
        case .idle: idle()
        case .ready: ready()
        case .thinking: think()
        case .working: work()
        case .writing: write()
        case .waving: wave()
        case .happy: cheer()
        case .sad: droop()
        case .stopped: doze()
        }
    }

    func stopTimers() {
        for timer in timers { timer.invalidate() }
        timers = []
    }

    // MARK: - The moods

    private func idle() {
        add(head, "breathe", keyframes("transform.translation.y", [0, -1.2, 0], duration: 3.2))
        every(3.8) { [weak self] in self?.blink() }
        every(9.5) { [weak self] in self?.glance(to: Bool.random() ? -3.5 : 3.5) }
    }

    private func ready() {
        let float = keyframes("transform.translation.y", [0, -4, 0], duration: 3)
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        add(head, "float", float)
        // The shadow narrows and pales as Astro rises off it.
        add(ground, "shadow", keyframes("transform.scale.x", [1, 0.78, 1], duration: 3))
        add(ground, "fade", keyframes("opacity", [1, 0.55, 1], duration: 3))
        let glow = keyframes("opacity", [0.35, 1, 0.35], duration: 2.4)
        for light in earLights { add(light, "glow", glow) }
        every(3.6) { [weak self] in self?.blink() }
        every(5.2) { [weak self] in self?.gesture() }
    }

    /// One of the things Astro does while it waits for a first task.
    private func gesture() {
        switch Int.random(in: 0 ..< 4) {
        case 0: lookDown()
        case 1: glance(to: Bool.random() ? -4 : 4)
        case 2: hello()
        default:
            blink()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                MainActor.assumeIsolated { self?.blink() }
            }
        }
    }

    /// A look down at the field, where the task will be written, and back.
    private func lookDown() {
        add(eyes, "look", keyframes("transform.translation.y", [0, 3.5, 3.5, 0], times: [0, 0.2, 0.75, 1], duration: 1.6,
                                    repeating: false))
    }

    /// A tilt of the head, the ears flashing and a glint beside it.
    private func hello() {
        add(head, "hello", keyframes("transform.rotation.z", [0, 0.14, -0.08, 0.04, 0], duration: 0.9, repeating: false))
        for light in earLights { add(light, "flash", keyframes("opacity", [1, 0.2, 1, 0.2, 1], duration: 0.6, repeating: false)) }
        let star = sparkles[1]
        let pop = keyframes("transform.scale", [0, 1.1, 0], times: [0, 0.4, 1], duration: 0.8, repeating: false)
        pop.fillMode = .both
        pop.isRemovedOnCompletion = false
        star.opacity = 1
        add(star, "pop", pop)
    }

    private func think() {
        // Head on one side, eyes up and wandering, as if working it out.
        add(head, "tilt", keyframes("transform.rotation.z", [0, -0.1, -0.1, 0.05, 0.05, 0],
                                    times: [0, 0.2, 0.45, 0.6, 0.85, 1], duration: 3.6))
        add(eyes, "wander", keyframes("transform.translation.x", [0, -3, -3, 3, 3, 0],
                                      times: [0, 0.15, 0.4, 0.55, 0.85, 1], duration: 2.8))
        add(eyes, "up", keyframes("transform.translation.y", [0, -2, -2, 0], times: [0, 0.2, 0.8, 1], duration: 2.8))
        for (index, dot) in thoughts.enumerated() {
            let fill = keyframes("opacity", [0, 0, 1, 1, 0], times: [0, Double(index) * 0.18, Double(index) * 0.18 + 0.12, 0.85, 1],
                                 duration: 1.8)
            add(dot, "fill", fill)
        }
        for light in earLights { add(light, "pulse", pulse(duration: 0.9)) }
        every(4.2) { [weak self] in self?.blink() }
    }

    private func work() {
        add(head, "bob", keyframes("transform.translation.y", [0, -2.4, 0, -1.2, 0], duration: 1.1))
        add(ground, "squeeze", keyframes("opacity", [1, 0.6, 1, 0.8, 1], duration: 1.1))
        scan.opacity = 1
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -9
        sweep.toValue = visor.bounds.width + 9
        sweep.duration = 1.4
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        add(scan, "sweep", sweep)
        for light in earLights { add(light, "pulse", pulse(duration: 0.5)) }
        every(2.6) { [weak self] in self?.glance(to: Bool.random() ? -2 : 2) }
        every(4.6) { [weak self] in self?.blink() }
    }

    private func write() {
        // Eyes down a little, along the line and back to its start, the way
        // a reader's go; the head keeps time with the words.
        add(eyes, "line", keyframes("transform.translation.x", [-3, 3, -3], times: [0, 0.82, 1], duration: 1.3))
        add(eyes, "down", keyframes("transform.translation.y", [1.5, 1.5], duration: 1.3))
        add(head, "beat", keyframes("transform.translation.y", [0, 0.9, 0], duration: 0.65))
        for light in earLights { add(light, "pulse", pulse(duration: 1.3)) }
        every(5) { [weak self] in self?.blink() }
    }

    private func wave() {
        add(head, "rock", keyframes("transform.rotation.z", [0, 0.12, -0.12, 0.08, 0], duration: 1.2, repeating: true))
        for (index, light) in earLights.enumerated() {
            let flash = keyframes("opacity", index == 0 ? [1, 0.15, 1, 1] : [1, 1, 0.15, 1], duration: 0.6)
            add(light, "flash", flash)
        }
        every(3) { [weak self] in self?.blink() }
    }

    private func cheer() {
        add(head, "hop", keyframes("transform.translation.y", [0, -7, 0, -2.5, 0], times: [0, 0.3, 0.6, 0.8, 1],
                                   duration: 0.7, repeating: false))
        add(head, "wiggle", keyframes("transform.rotation.z", [0, 0.08, -0.08, 0], duration: 0.7, repeating: false))
        for (index, star) in sparkles.enumerated() {
            let pop = keyframes("transform.scale", [0, 1.15, 0.9, 0], times: [0, 0.35, 0.7, 1], duration: 0.9, repeating: false)
            pop.beginTime = CACurrentMediaTime() + 0.15 + Double(index) * 0.12
            // Small before its turn and gone after it, not left standing.
            pop.fillMode = .both
            pop.isRemovedOnCompletion = false
            star.opacity = 1
            add(star, "pop", pop)
        }
        breathe(after: 0.7)
    }

    /// The idle float, on top of whatever else the head is doing, so a mood
    /// that has finished its moment still looks alive.
    private func breathe(after delay: CFTimeInterval = 0, depth: CGFloat = 1.2, duration: CFTimeInterval = 3.2) {
        let float = keyframes("transform.translation.y", [0, -depth, 0], duration: duration)
        float.isAdditive = true
        float.beginTime = CACurrentMediaTime() + delay
        add(head, "alive", float)
    }

    private func droop() {
        add(head, "sink", keyframes("transform.translation.y", [0, 3], duration: 0.5, repeating: false, holds: true))
        add(head, "hang", keyframes("transform.rotation.z", [0, 0.06], duration: 0.5, repeating: false, holds: true))
        breathe(after: 0.5, depth: 0.8, duration: 4.4)
    }

    private func doze() {
        add(head, "doze", keyframes("transform.translation.y", [0, 1.5, 0], duration: 4.2))
        every(6) { [weak self] in self?.blink() }
    }

    // MARK: - Now and then

    func blink() {
        // Arcs, smiling or drooping, have no lid to close.
        guard ![.happy, .sad].contains(mood) else { return }
        let closed = eyePaths(for: mood, open: 0.1)
        for (eye, path) in [(leftEye, closed.0), (rightEye, closed.1)] {
            let animation = CABasicAnimation(keyPath: "path")
            animation.toValue = path
            animation.duration = 0.09
            animation.autoreverses = true
            eye.add(animation, forKey: "blink")
        }
    }

    /// A look to one side and back.
    func glance(to offset: CGFloat) {
        let look = keyframes("transform.translation.x", [0, offset, offset, 0], times: [0, 0.2, 0.75, 1], duration: 1.3,
                             repeating: false)
        add(eyes, "glance", look)
    }

    // MARK: - Building blocks

    private func every(_ interval: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        timers.append(timer)
    }

    private func add(_ layer: CALayer, _ key: String, _ animation: CAAnimation) {
        layer.add(animation, forKey: key)
    }

    private func keyframes(
        _ path: String, _ values: [CGFloat], times: [Double]? = nil, duration: CFTimeInterval, repeating: Bool = true,
        holds: Bool = false
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: path)
        animation.values = values
        animation.keyTimes = times?.map { NSNumber(value: $0) }
        animation.duration = duration
        animation.repeatCount = repeating ? .infinity : 1
        animation.calculationMode = .cubic
        if holds {
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        }
        return animation
    }

    private func pulse(duration: CFTimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0.3
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        return animation
    }
}
