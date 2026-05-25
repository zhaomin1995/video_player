import Foundation

enum RepeatMode: String {
    case off
    case one
    case all
}

class PlaylistManager {
    private(set) var items: [URL] = []
    private(set) var currentIndex: Int = -1

    var repeatMode: RepeatMode = .off
    var shuffle = false

    var currentItem: URL? {
        guard currentIndex >= 0, currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    var hasNext: Bool {
        switch repeatMode {
        case .off: return currentIndex < items.count - 1
        case .one: return true
        case .all: return !items.isEmpty
        }
    }

    var hasPrevious: Bool {
        switch repeatMode {
        case .off: return currentIndex > 0
        case .one: return true
        case .all: return !items.isEmpty
        }
    }

    func addItem(_ url: URL) {
        items.append(url)
    }

    func removeItem(at index: Int) {
        guard index >= 0, index < items.count else { return }
        items.remove(at: index)
        if currentIndex >= items.count {
            currentIndex = items.count - 1
        }
    }

    func selectItem(at index: Int) -> URL? {
        guard index >= 0, index < items.count else { return nil }
        currentIndex = index
        return items[index]
    }

    func next() -> URL? {
        guard !items.isEmpty else { return nil }

        switch repeatMode {
        case .one:
            return currentItem
        case .off:
            if shuffle {
                let remaining = items.indices.filter { $0 != currentIndex }
                guard let nextIndex = remaining.randomElement() else { return nil }
                currentIndex = nextIndex
            } else {
                guard currentIndex < items.count - 1 else { return nil }
                currentIndex += 1
            }
        case .all:
            if shuffle {
                let remaining = items.indices.filter { $0 != currentIndex }
                currentIndex = remaining.randomElement() ?? 0
            } else {
                currentIndex = (currentIndex + 1) % items.count
            }
        }

        return currentItem
    }

    func previous() -> URL? {
        guard !items.isEmpty else { return nil }

        switch repeatMode {
        case .one:
            return currentItem
        case .off:
            guard currentIndex > 0 else { return nil }
            currentIndex -= 1
        case .all:
            currentIndex = (currentIndex - 1 + items.count) % items.count
        }

        return currentItem
    }

}
