import Foundation
import Testing
@testable import Locky

@Suite struct IntruderPolicyTests {
    @Test func thePhotoComesOnceAtTheSetWrongPassword() throws {
        let sandbox = try Sandbox()
        try sandbox.write("settings.json", #"{ "intruder_photo": 3 }"#)
        let settings = Settings.load(config: sandbox.config).settings
        var lock = IntruderPolicy(settings: settings)
        #expect(lock.threshold == 3)
        #expect((1...6).map { _ in lock.wrongPassword() } == [false, false, true, false, false, false])
        // The next lock counts from the start again.
        var next = IntruderPolicy(settings: settings)
        #expect((1...3).map { _ in next.wrongPassword() } == [false, false, true])
    }

    @Test(arguments: [nil, .int(0), .int(-2), .double(2.5), .string("3"), .bool(true)] as [LuaValue?])
    func anythingButAWholeNumberAboveZeroIsOff(_ value: LuaValue?) {
        var lock = IntruderPolicy(settings: Settings(value.map { ["intruder_photo": $0] } ?? [:]))
        #expect(lock.threshold == nil)
        #expect((1...10).allSatisfy { _ in !lock.wrongPassword() })
    }
}

/// A camera that never touches the hardware: it records each call and answers as told.
private final class FakeCamera: CameraSession, @unchecked Sendable {
    /// "start" or "shoot": the call that hangs until `release()`.
    let hangsIn: String?
    let startError: IntruderCamera.Failure?
    let photo = Data("not really a jpeg".utf8)
    private let released = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _onMainThread = false

    init(hangsIn: String? = nil, startError: IntruderCamera.Failure? = nil) {
        self.hangsIn = hangsIn
        self.startError = startError
    }

    var calls: [String] { lock.withLock { _calls } }
    var calledOnMainThread: Bool { lock.withLock { _onMainThread } }

    func start() throws {
        record("start")
        if hangsIn == "start" { hang() }
        if let startError { throw startError }
    }

    func shoot(until deadline: DispatchTime) throws -> Data {
        record("shoot")
        if hangsIn == "shoot" { hang() }
        return photo
    }

    func stop() { record("stop") }

    func release() { released.signal() }

    /// Waits for `release()`, or 10 s, so that a broken timeout fails the test instead of hanging the run.
    private func hang() {
        _ = released.wait(timeout: .now() + 10)
    }

    private func record(_ call: String) {
        let main = Thread.isMainThread
        lock.withLock {
            _calls.append(call)
            _onMainThread = _onMainThread || main
        }
    }
}

@Suite struct IntruderCameraTests {
    private func makeCamera(_ fake: FakeCamera, _ sandbox: Sandbox, timeout: Double = 3) -> IntruderCamera {
        IntruderCamera(log: IntruderLog(folder: sandbox.root.appending(path: "Intruders")), settle: 0.01, timeout: timeout, session: { fake })
    }

    @MainActor @Test func thePhotoIsSavedPrivatelyAndTheCameraTurnedOffOffTheMainThread() async throws {
        let sandbox = try Sandbox()
        let fake = FakeCamera()
        let camera = makeCamera(fake, sandbox)
        let url = try await camera.capture()
        #expect(try Data(contentsOf: url) == fake.photo)
        #expect(camera.log.photos().map { $0.url } == [url])
        let mode = try FileManager.default.attributesOfItem(atPath: camera.log.folder.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
        #expect(await eventually { @Sendable in fake.calls == ["start", "shoot", "stop"] })
        #expect(!fake.calledOnMainThread)
    }

    /// The capture answers at its deadline while the camera still hangs, and turns the camera off once it returns.
    @Test(arguments: ["start", "shoot"])
    func aHangingCameraTimesOutAndIsStillTurnedOff(_ call: String) async throws {
        let sandbox = try Sandbox()
        let fake = FakeCamera(hangsIn: call)
        let camera = makeCamera(fake, sandbox, timeout: 0.2)
        let began = Date()
        await #expect(throws: IntruderCamera.Failure.timedOut) { try await camera.capture() }
        #expect(fake.calls.last == call)
        // Far below the stand-in's own 10 s limit, with room for a busy test run.
        #expect(Date().timeIntervalSince(began) < 5)
        fake.release()
        #expect(await eventually { fake.calls.last == "stop" })
        #expect(camera.log.photos().isEmpty)
    }

    @Test func aCameraThatCannotStartIsStillTurnedOff() async throws {
        let sandbox = try Sandbox()
        let fake = FakeCamera(startError: .notAllowed)
        await #expect(throws: IntruderCamera.Failure.notAllowed) { try await makeCamera(fake, sandbox).capture() }
        #expect(await eventually { fake.calls == ["start", "stop"] })
    }
}

@Suite struct IntruderLogTests {
    private func date(day: Int, hour: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: 43, second: 5)))
    }

    @Test func aPhotoIsNamedForItsTimeInAPrivateFolder() throws {
        let sandbox = try Sandbox()
        let log = IntruderLog(folder: sandbox.root.appending(path: "Intruders"))
        // A folder that exists already, readable by others, becomes private too.
        try FileManager.default.createDirectory(at: log.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let url = try log.save(Data("x".utf8), at: date(day: 12, hour: 19))
        #expect(url.lastPathComponent == "2026-10-12 19.43.05.jpg")
        #expect(try FileManager.default.attributesOfItem(atPath: log.folder.path)[.posixPermissions] as? Int == 0o700)
    }

    @Test func photosListNewestFirstAndDeleteOneOrAll() throws {
        let sandbox = try Sandbox()
        let fm = FileManager.default
        let log = IntruderLog(folder: sandbox.root.appending(path: "Intruders"))
        #expect(log.photos().isEmpty)
        let saved = try [date(day: 1, hour: 10), date(day: 3, hour: 9), date(day: 2, hour: 23)].map { try log.save(Data("x".utf8), at: $0) }
        // A photo renamed in Finder keeps its place by its file date; a file that is no photo is left out.
        let renamed = log.folder.appending(path: "front door.jpg")
        try Data("x".utf8).write(to: renamed)
        try fm.setAttributes([.modificationDate: date(day: 2, hour: 12)], ofItemAtPath: renamed.path)
        try "notes".write(to: log.folder.appending(path: "notes.txt"), atomically: true, encoding: .utf8)

        let photos = log.photos()
        #expect(photos.map { $0.url.lastPathComponent } == [saved[1], saved[2], renamed, saved[0]].map(\.lastPathComponent))
        #expect(try photos.map { $0.date } == [date(day: 3, hour: 9), date(day: 2, hour: 23), date(day: 2, hour: 12), date(day: 1, hour: 10)])

        try log.delete(photos[1].url)
        #expect(log.photos().map { $0.url } == [saved[1], renamed, saved[0]])
        let outside = sandbox.root.appending(path: "keep.jpg")
        try Data("x".utf8).write(to: outside)
        #expect(throws: (any Error).self) { try log.delete(outside) }
        #expect(fm.fileExists(atPath: outside.path))
        // Paths that name the folder itself, or a folder that looks like a photo, delete nothing.
        try fm.createDirectory(at: log.folder.appending(path: "album.jpg"), withIntermediateDirectories: true)
        for path in [log.folder.appending(path: "."), log.folder.appending(path: "album.jpg/.."), log.folder.appending(path: "album.jpg")] {
            #expect(throws: (any Error).self) { try log.delete(path) }
        }
        #expect(fm.fileExists(atPath: log.folder.appending(path: "notes.txt").path))
        #expect(!log.photos().contains { $0.url.lastPathComponent == "album.jpg" })

        try log.deleteAll()
        #expect(log.photos().isEmpty)
        #expect(fm.fileExists(atPath: log.folder.appending(path: "notes.txt").path))
        #expect(fm.fileExists(atPath: log.folder.appending(path: "album.jpg").path))
    }
}
