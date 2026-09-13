import AppKit
import ClipboardCore

/// Connects history quick-save actions with the independent library.
final class FavoritesCoordinator {
    private(set) var library = FavoritesLibraryController()
    private(set) var repository: FavoritesRepository?
    private var membershipCache: [UUID:Bool] = [:]
    private var errorMessage = L10n.tr("收藏库尚未就绪。")
    var onMessage: ((String) -> Void)?
    var onChanged: (() -> Void)?
    var onCopy: ((HistoryEntry) -> Bool)? {
        didSet { library.onCopy = onCopy }
    }
    init() { library.onChange = { [weak self] in self?.onChanged?() } }
    func refreshLanguage() {
        library.refreshLanguage()
    }
    func open(store: AppDataStore, available: Bool) {
        repository?.close(); repository = nil;membershipCache.removeAll()
        do {
            guard available else { throw LocalStorageError(L10n.tr("当前存储不可用，请通过“数据与恢复”重试。")) }
            repository = try FavoritesRepository(directoryURL: store.directoryURL)
            library.setRepository(repository)
        } catch { errorMessage = error is DataFormatError ? L10n.tr("收藏由更新版本创建，请使用更新版本打开。原文件已保留。") : error.localizedDescription; library.setRepository(nil,message:errorMessage) }
    }
    func suspend() {
        library.setRepository(nil,message:L10n.tr("正在迁移存储，新复制暂存于内存，完成后保存。"))
    }
    func isFavorite(_ entry: HistoryEntry) -> Bool {
        if library.isMutating { return membershipCache[entry.id] ?? false }
        let result = (try? repository?.favoriteID(for:entry.payload)) != nil
        membershipCache[entry.id] = result
        if membershipCache.count > 100 { membershipCache = [entry.id:result] }
        return result
    }
    func toggle(_ entry: HistoryEntry) {
        guard !library.isMutating else { onMessage?(L10n.tr("收藏正在保存，请稍后操作。"));return }
        guard let repository else { onMessage?(errorMessage);return }
        do {
            if let id = try repository.favoriteID(for:entry.payload) {
                try repository.remove(ids:[id]);onMessage?(L10n.tr("已取消收藏，普通历史仍保留。"))
            } else {
                try repository.add(entry, thumbnail: FavoriteThumbnail.make(for:entry.payload));onMessage?(L10n.tr("已收藏到“未分类”，可在收藏库中整理。"))
            }
            library.reload(); onChanged?()
        } catch { onMessage?(error.localizedDescription) }
    }
    func present() { library.present() }
    func shutdown() { library.finishPendingChanges(); library.previews.closeAll(); repository?.close() }
}
