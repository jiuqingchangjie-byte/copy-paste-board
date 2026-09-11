import Foundation

/// One pending row at a time. Repeated movement within a row does not restart
/// the delay; leaving, scrolling, reloading or opening a menu cancels it.
final class HoverPreviewScheduler {
    private var timer: Timer?
    private var pendingID: UUID?

    func schedule(id: UUID, delay: TimeInterval, action: @escaping () -> Void) {
        guard pendingID != id else { return }
        cancel()
        pendingID = id
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.pendingID == id else { return }
            self.timer = nil
            action()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        pendingID = nil
    }

    deinit { timer?.invalidate() }
}
