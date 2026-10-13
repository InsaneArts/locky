import AVFoundation
import Foundation

/// When to take the intruder photo: settings.json's `"intruder_photo": 3` takes one at the third wrong password
/// of a lock. A missing key, or anything but a whole number above 0, turns it off. Make one per lock.
struct IntruderPolicy {
    /// The wrong password that takes the photo; nil when the feature is off.
    let threshold: Int?
    private var wrong = 0

    init(settings: Settings) {
        threshold = settings["intruder_photo"].int.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Counts a wrong password. True exactly once per lock: when the count reaches the threshold.
    mutating func wrongPassword() -> Bool {
        wrong += 1
        return wrong == threshold
    }
}

/// Locky's permission to use the camera. Ask for it when the user turns intruder photos on: IntruderCamera
/// never asks, so no system prompt can appear during a lock.
enum CameraAccess {
    static var status: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    /// Shows the system prompt the first time; later calls return the saved answer without asking.
    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

/// A camera, on for one photo. IntruderCamera calls start, shoot, and stop in that order on a queue of its
/// own, and calls stop even when start or shoot fails. Tests pass their own, so no test turns a camera on.
protocol CameraSession {
    /// Starts the camera. Blocks until it runs.
    func start() throws
    /// Takes one JPEG. Blocks until it arrives, or until `deadline`.
    func shoot(until deadline: DispatchTime) throws -> Data
    /// Turns the camera off. Blocks until it is off.
    func stop()
}

/// Takes one photo with the built-in camera (or the default one) and saves it in the intruder folder. The
/// camera works off the main thread and is always turned off again.
final class IntruderCamera: Sendable {
    enum Failure: Error, Equatable {
        /// CameraAccess.status is not `.authorized`.
        case notAllowed
        /// No camera, or it would not start.
        case noCamera
        /// The camera ran but gave no JPEG.
        case noPhoto
        case timedOut
    }

    let log: IntruderLog
    /// Seconds for exposure to settle once the camera runs, and for the whole capture. Tests shorten them.
    let settle: Double
    let timeout: Double
    private let makeSession: @Sendable () -> any CameraSession

    init(log: IntruderLog = IntruderLog(), settle: Double = 0.5, timeout: Double = 5,
         session: @escaping @Sendable () -> any CameraSession = { AVCameraSession() }) {
        self.log = log
        self.settle = settle
        self.timeout = timeout
        makeSession = session
    }

    /// Takes the photo and returns its file. Throws a Failure, or AVFoundation's error.
    func capture() async throws -> URL {
        let deadline = DispatchTime.now() + timeout
        let photo: Data = try await withCheckedThrowingContinuation { continuation in
            let reply = Reply(continuation)
            // Answers at the deadline even when the camera hangs in start or shoot. A queue of its own: on a busy Mac,
            // a timer on DispatchQueue.global() can fire seconds late.
            DispatchQueue(label: "Locky.IntruderCamera.deadline").asyncAfter(deadline: deadline) {
                reply.resume(with: .failure(Failure.timedOut))
            }
            DispatchQueue(label: "Locky.IntruderCamera").async {
                let session = self.makeSession()
                reply.resume(with: Result {
                    try session.start()
                    Thread.sleep(forTimeInterval: self.settle)
                    guard DispatchTime.now() < deadline else { throw Failure.timedOut }
                    return try session.shoot(until: deadline)
                })
                session.stop()
            }
        }
        return try log.save(photo)
    }
}

/// Resumes a continuation once: the first answer wins, later ones are dropped.
private final class Reply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?

    init(_ continuation: CheckedContinuation<Data, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Data, any Error>) {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }
}

/// The camera through AVFoundation. Made and used on IntruderCamera's queue only.
final class AVCameraSession: CameraSession {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()

    func start() throws {
        // Before the user has answered, using the camera makes macOS ask, and the question would come during a lock.
        guard CameraAccess.status == .authorized else { throw IntruderCamera.Failure.notAllowed }
        guard let device = Self.camera() else { throw IntruderCamera.Failure.noCamera }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        let added = session.canAddInput(input) && session.canAddOutput(output)
        if added {
            session.addInput(input)
            session.addOutput(output)
        }
        session.commitConfiguration()
        guard added else { throw IntruderCamera.Failure.noCamera }
        session.startRunning()
        guard session.isRunning else { throw IntruderCamera.Failure.noCamera }
    }

    func shoot(until deadline: DispatchTime) throws -> Data {
        // capturePhoto raises an Objective-C exception, which would end the app and the lock with it, when the
        // video connection is not running or the output has no JPEG.
        guard session.isRunning, let connection = output.connection(with: .video), connection.isEnabled, connection.isActive
        else { throw IntruderCamera.Failure.noCamera }
        guard output.availablePhotoCodecTypes.contains(.jpeg) else { throw IntruderCamera.Failure.noPhoto }
        let delegate = PhotoDelegate()
        output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: delegate)
        guard delegate.done.wait(timeout: deadline) == .success else { throw IntruderCamera.Failure.timedOut }
        return try delegate.result.get()
    }

    func stop() {
        session.stopRunning()
    }

    /// The built-in camera, unless its lid is closed; otherwise the default camera.
    private static func camera() -> AVCaptureDevice? {
        let builtIn = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        // Without an Info.plist opt-in, an iPhone used as a Continuity Camera reports as built in too.
        return builtIn.devices.first { !$0.isContinuityCamera && !$0.isSuspended } ?? AVCaptureDevice.default(for: .video)
    }
}

/// Receives the photo on AVFoundation's queue. `result` is set before `done` signals.
private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    private(set) var result: Result<Data, any Error> = .failure(IntruderCamera.Failure.noPhoto)

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        }
        done.signal()
    }
}

/// The intruder photos: one JPEG per photo, named for the time it was taken, in a folder only this user may
/// open. The window lists and deletes them.
struct IntruderLog {
    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Locky/Intruders")
    }

    var folder = Self.defaultFolder

    /// Every photo with the time it was taken, newest first.
    func photos() -> [(url: URL, date: Date)] {
        let formatter = Self.nameFormatter()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && $0.lowercased().hasSuffix(".jpg") && Self.isRegularFile(folder.appending(path: $0)) }
            .map { name in
                let url = folder.appending(path: name)
                // A photo renamed in Finder keeps its place by its file date.
                let date = formatter.date(from: url.deletingPathExtension().lastPathComponent)
                    ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return (url, date)
            }
            .sorted { ($0.date, $0.url.lastPathComponent) > ($1.date, $1.url.lastPathComponent) }
    }

    /// Deletes one photo: only a file `photos()` lists, so a wrong URL ("Intruders/.", a folder) deletes nothing else.
    func delete(_ photo: URL) throws {
        let target = photo.standardizedFileURL.resolvingSymlinksInPath().path
        guard photos().contains(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath().path == target }) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: photo])
        }
        try FileManager.default.removeItem(at: photo)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    /// Deletes every photo, and nothing else in the folder.
    func deleteAll() throws {
        for photo in photos() { try FileManager.default.removeItem(at: photo.url) }
    }

    /// Writes "<yyyy-MM-dd HH.mm.ss>.jpg", then prunes. The folder gets mode 0700 even when it exists: the photos
    /// are private.
    func save(_ photo: Data, at date: Date = Date()) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let url = folder.appending(path: Self.nameFormatter().string(from: date) + ".jpg")
        try photo.write(to: url, options: .atomic)
        prune(now: date)
        return url
    }

    /// Keeps the newest 20 photos, and none older than 30 days: after each photo, and at launch.
    func prune(now: Date = Date()) {
        for (index, photo) in photos().enumerated() where index >= 20 || now.timeIntervalSince(photo.date) > 30 * 86_400 {
            try? FileManager.default.removeItem(at: photo.url)
        }
    }

    /// Names that sort by time, with "." for ":", which Finder shows as "/".
    private static func nameFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }
}
