import AVFoundation

enum ABLoopState {
    case inactive
    case settingA(CMTime)
    case active(a: CMTime, b: CMTime)
}

protocol ABLoopDelegate: AnyObject {
    func abLoopStateChanged(_ state: ABLoopState)
    func abLoopShouldSeek(to time: CMTime)
}

class ABLoopController {
    weak var delegate: ABLoopDelegate?

    private(set) var state: ABLoopState = .inactive
    var gap: TimeInterval = 0

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    func toggle(currentTime: CMTime) {
        switch state {
        case .inactive:
            state = .settingA(currentTime)
            delegate?.abLoopStateChanged(state)

        case .settingA(let a):
            if currentTime > a {
                state = .active(a: a, b: currentTime)
            } else {
                state = .active(a: currentTime, b: a)
            }
            delegate?.abLoopStateChanged(state)

        case .active:
            state = .inactive
            delegate?.abLoopStateChanged(state)
        }
    }

    func checkLoop(currentTime: CMTime) {
        guard case .active(let a, let b) = state else { return }
        if CMTimeCompare(currentTime, b) >= 0 {
            if gap > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + gap) { [weak self] in
                    self?.delegate?.abLoopShouldSeek(to: a)
                }
            } else {
                delegate?.abLoopShouldSeek(to: a)
            }
        }
    }

    func clear() {
        state = .inactive
        delegate?.abLoopStateChanged(state)
    }
}
