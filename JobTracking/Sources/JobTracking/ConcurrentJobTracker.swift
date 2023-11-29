public class ConcurrentJobTracker<Key: Hashable, Output, E: Error>: AsyncJobTracking {

    private let memOptions: MemoizationOptions
    private let jobworker: JobWorker<Key, Output, Failure>
    private var jobStatus: [Key: Task<Output, Failure>] = [:]
    private var jobAnswers: [Key: Result<Output, Failure>] = [:]

    public required init(memoizing: MemoizationOptions, worker: @escaping JobWorker<Key, Output, Failure>) {
        memOptions = memoizing
        jobworker = worker
    }

    public typealias Key = Key
    public typealias Output = Output
    public typealias Failure = E
    enum MyError : Error{
        case runtimeError(String)
    }
    public func startJob(for key: Key) async throws -> Output {
        if memOptions.contains(.started) {
            if let existingTask = jobStatus[key] {
                return try await existingTask.value
            } else {
                let task = Task { [weak self] in
                    guard let self = self else { throw MyError.runtimeError("Self is nil") }
                    return try await withUnsafeThrowingContinuation { continuation in
                        self.jobworker(key) { result in
                            switch self.memOptions {
                            case .succeeded:
                                switch result {
                                case .failure(_):
                                    self.jobAnswers[key] = self.jobAnswers[key]
                                case .success(_):
                                    self.jobAnswers[key] = result
                                }
                            case .failed:
                                switch result {
                                case .failure(_):
                                    self.jobAnswers[key] = result
                                case .success(_):
                                    self.jobAnswers[key] = self.jobAnswers[key]
                                }
                            case .completed:
                                self.jobAnswers[key] = result
                            default:
                                self.jobAnswers[key] = self.jobAnswers[key]
                            }
                            continuation.resume(with: result)
                        }
                    }
                }
                jobStatus[key] = task as? Task<Output, Failure>
                return try await task.value
            }
        } else {
            return try await withUnsafeThrowingContinuation { continuation in
                self.jobworker(key) { result in
                    continuation.resume(with: result)
                }
            }
        }
    }
}
