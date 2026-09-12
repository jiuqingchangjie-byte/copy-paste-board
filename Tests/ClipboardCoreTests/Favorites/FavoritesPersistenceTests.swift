import Foundation
import Testing
@testable import ClipboardCore

struct FavoritesPersistenceTests {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }
    @Test func favoritesExceedFiftyDeduplicateAndRestoreWithoutChangingHistory() throws {
        let dir = try temporary(); defer { try? FileManager.default.removeItem(at:dir) }
        var repo: FavoritesRepository? = try FavoritesRepository(directoryURL:dir)
        var ids: [UUID] = []
        for i in 0..<137 { ids.append(try repo!.add(HistoryEntry(payload:.text("item-\(i) 😀")))) }
        let original = HistoryEntry(payload:.text("item-0 😀"))
        #expect(try repo!.add(original) == ids[0])
        #expect(try repo!.page().total == 137)
        #expect(try repo!.page(offset:100).items.count == 37)
        #expect(try repo!.page().items.count == 100)
        var history = History(entries:[original],maxCount:1);history.clear()
        #expect(try repo!.favoriteID(for:original.payload) == ids[0])
        repo!.close();repo = nil
        let restored = try FavoritesRepository(directoryURL:dir)
        #expect(try restored.page().total == 137)
        #expect(try restored.entry(id:ids[0])?.payload == original.payload)
        #expect(history.entries.isEmpty)
    }
    @Test func folderMoveRenameDeleteAndScopedClearAreIsolated() throws {
        let dir = try temporary();defer { try? FileManager.default.removeItem(at:dir) }
        let repo = try FavoritesRepository(directoryURL:dir)
        let a = try repo.createFolder(name:" 工作 "), b = try repo.createFolder(name:"私人")
        let first = try repo.add(HistoryEntry(payload:.text("alpha_%'😀")),folderID:a)
        let second = try repo.add(HistoryEntry(payload:.text("beta")),folderID:a)
        let third = try repo.add(HistoryEntry(payload:.text("gamma")),folderID:b)
        #expect(try repo.page(query:"_%'").items.map(\.id) == [first])
        try repo.move(ids:[first,second],to:b)
        #expect(try repo.page(scope:.folder(a)).total == 0)
        #expect(try repo.page(scope:.folder(b)).total == 3)
        try repo.renameFolder(id:b,name:"资料")
        #expect(try repo.folders().contains { $0.id == b && $0.name == "资料" && $0.count == 3 })
        #expect(throws: (any Error).self) { try repo.renameFolder(id:b,name:"工作") }
        #expect(throws: (any Error).self) { try repo.createFolder(name:"未分类") }
        #expect(throws: (any Error).self) { try repo.createFolder(name:"  ") }
        try repo.deleteFolder(id:b)
        #expect(try repo.page(scope:.unfiled).total == 3)
        try repo.move(ids:[third],to:a)
        try repo.clear(scope:.unfiled)
        #expect(try repo.page().items.map(\.id) == [third])
        try repo.clear()
        #expect(try repo.page().total == 0)
        #expect(try repo.folders().count == 1)
    }
    @Test func allPayloadsRestoreExactlyAndInvalidPayloadsDoNotWrite() throws {
        let dir = try temporary();defer { try? FileManager.default.removeItem(at:dir) }
        let repo = try FavoritesRepository(directoryURL:dir)
        for payload in [ClipPayload.text(" \r\n{\"id\":900719925474099312345}\t"),.image(Data([0,1,2,255])),.files(["file:///tmp/a%20b.txt"])] {
            let id = try repo.add(HistoryEntry(payload:payload))
            #expect(try repo.entry(id:id)?.payload == payload)
        }
        #expect(throws: (any Error).self) { try repo.add(HistoryEntry(payload:.text(""))) }
        #expect(throws: (any Error).self) { try repo.add(HistoryEntry(payload:.text(String(repeating:"a",count:8*1024*1024+1)))) }
        #expect(try repo.page().total == 3)
    }
    @Test func batchFailureRollsBackAndFutureVersionIsNotRebuilt() throws {
        let dir = try temporary();defer { try? FileManager.default.removeItem(at:dir) }
        let repo = try FavoritesRepository(directoryURL:dir)
        let ids = try Set((0..<3).map { try repo.add(HistoryEntry(payload:.text("\($0)"))) })
        let connection = try SQLiteDatabase(url:repo.fileURL)
        try connection.run("CREATE TABLE delete_counter(n INTEGER)")
        try connection.run("INSERT INTO delete_counter VALUES(0)")
        try connection.run("CREATE TRIGGER fail_second_delete BEFORE DELETE ON favorites BEGIN UPDATE delete_counter SET n=n+1; SELECT CASE WHEN (SELECT n FROM delete_counter)>1 THEN RAISE(ABORT,'test failure') END; END")
        #expect(throws: (any Error).self) { try repo.remove(ids:ids) }
        #expect(try repo.page().total == 3)
        try connection.run("PRAGMA user_version=99")
        connection.close();repo.close()
        let before = try Data(contentsOf:repo.fileURL)
        #expect(throws: DataFormatError.self) { try FavoritesRepository(directoryURL:dir) }
        #expect(try Data(contentsOf:repo.fileURL) == before)
    }
    @Test func migrationCommitsPointerLastAndRetainsOriginalBytes() throws {
        let root = try temporary();defer { try? FileManager.default.removeItem(at:root) }
        let location = StorageLocation(applicationURL:root.appendingPathComponent("Install/App.app"))
        let source = try location.resolve()
        let entry = HistoryEntry(payload:.text("saved before relocation"))
        let settings = AppSettings(maxHistoryCount:17)
        try source.history.save([entry]);try source.saveSettings(settings)
        let repo = try FavoritesRepository(directoryURL:source.directoryURL)
        let folder = try repo.createFolder(name:"重要");let favorite = try repo.add(entry,folderID:folder);repo.close()
        let originalBytes = try Data(contentsOf:source.history.fileURL)
        let destination = root.appendingPathComponent("NewData")
        let moved = try StorageRelocator.migrate(source:source,to:destination,location:location)
        #expect(try location.resolve().directoryURL == moved.directoryURL)
        #expect(try moved.history.load() == [entry])
        #expect(try moved.loadSettings() == settings)
        #expect(try Data(contentsOf:source.history.fileURL) == originalBytes)
        let reopened = try FavoritesRepository(directoryURL:moved.directoryURL)
        #expect(try reopened.entry(id:favorite)?.payload == entry.payload)
        #expect(try reopened.folders().first?.id == folder)
        reopened.close()
        try FileManager.default.moveItem(at:destination,to:root.appendingPathComponent("Unavailable"))
        #expect(throws: (any Error).self) { try location.resolve() }
        #expect(!FileManager.default.fileExists(atPath:destination.path))
    }
    @Test func unsafeDestinationAndFailedPointerNeverReplaceSourceOrExistingData() throws {
        let root = try temporary();defer { try? FileManager.default.removeItem(at:root) }
        let location = StorageLocation(applicationURL:root.appendingPathComponent("Install/App.app"))
        let source = try location.resolve()
        try source.history.save([HistoryEntry(payload:.text("original"))]);try source.saveSettings(AppSettings())
        let repo = try FavoritesRepository(directoryURL:source.directoryURL);repo.close()
        let occupied = root.appendingPathComponent("Occupied")
        try FileManager.default.createDirectory(at:occupied,withIntermediateDirectories:true)
        try Data("keep".utf8).write(to:occupied.appendingPathComponent("precious.txt"))
        #expect(throws: (any Error).self) { try StorageRelocator.migrate(source:source,to:occupied,location:location) }
        #expect(try String(contentsOf:occupied.appendingPathComponent("precious.txt"),encoding:.utf8) == "keep")
        #expect(throws: (any Error).self) { try StorageRelocator.migrate(source:source,to:source.directoryURL.appendingPathComponent("Nested"),location:location) }
        // An ordinary file at the dedicated config-directory path makes pointer saving fail.
        try Data("not a directory".utf8).write(to:location.pointerURL.deletingLastPathComponent())
        #expect(throws: (any Error).self) { try StorageRelocator.migrate(source:source,to:root.appendingPathComponent("Copy"),location:location) }
        #expect(try location.resolve().directoryURL == source.directoryURL)
        #expect(try source.history.load().first?.payload == .text("original"))
    }
    @Test func killedWriterRestoresCommittedDataAndRollsBackIncompleteDeletion() throws {
        let root = try temporary();defer { try? FileManager.default.removeItem(at:root) }
        let project = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let helper = root.appendingPathComponent("main.swift")
        try """
        import Foundation
        import Darwin
        let directory = URL(fileURLWithPath:CommandLine.arguments[1])
        let repo = try FavoritesRepository(directoryURL:directory)
        if CommandLine.arguments[2] == "commit" {
            for i in 0..<70 { try repo.add(HistoryEntry(payload:.text("durable-\\(i)"))) }
            try HistoryStorage(fileURL:directory.appendingPathComponent("history.json")).save([HistoryEntry(payload:.text("durable history"))])
        } else {
            let db = try SQLiteDatabase(url:repo.fileURL)
            try db.run("BEGIN IMMEDIATE")
            try db.run("DELETE FROM favorites")
        }
        kill(getpid(), SIGKILL)
        """.write(to:helper,atomically:true,encoding:.utf8)
        let enumerator = FileManager.default.enumerator(at:project.appendingPathComponent("Sources/ClipboardCore"),includingPropertiesForKeys:nil)!
        var sources:[String] = []
        while let file = enumerator.nextObject() as? URL { if file.pathExtension == "swift" { sources.append(file.path) } }
        let executable = root.appendingPathComponent("crash-writer")
        let build = Process();build.executableURL = URL(fileURLWithPath:"/usr/bin/swiftc")
        build.arguments = sources + [helper.path,"-o",executable.path,"-lsqlite3"]
        try build.run();build.waitUntilExit();#expect(build.terminationStatus == 0)
        let data = root.appendingPathComponent("Data")
        for mode in ["commit","rollback"] {
            let child = Process();child.executableURL = executable;child.arguments = [data.path,mode]
            try child.run();child.waitUntilExit()
            #expect(child.terminationReason == .uncaughtSignal)
            let reopened = try FavoritesRepository(directoryURL:data)
            #expect(try reopened.page().total == 70)
            #expect(try HistoryStorage(fileURL:data.appendingPathComponent("history.json")).load().first?.payload == .text("durable history"))
            reopened.close()
        }
    }
}
