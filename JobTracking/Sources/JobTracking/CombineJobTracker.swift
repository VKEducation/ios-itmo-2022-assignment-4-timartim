import Combine
import Foundation

public class CombineJobTracker<Key : Hashable, Output, Failure : Error> : PublishingJobTracking{
    
    public typealias JobPublisher = AnyPublisher<Result<Output, Failure>, Never>
    public typealias JobMap = [Key: JobPublisher]
    public typealias Key = Key
    var jobmap: JobMap = [:]
    public typealias Output = Output
    public typealias Failure = Failure
    private let memOptions: MemoizationOptions
    private let jobworker: JobWorker<Key, Output, Failure>
    let backgroundQ = DispatchQueue.global(qos: .utility)
    public required init(memoizing: MemoizationOptions, worker: @escaping JobWorker<Key, Output, Failure>) {
        memOptions = memoizing
        jobworker = worker
    }
    private class GCDJobPublisher<Key : Hashable, Output, Failure : Error>: Publisher {
        func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, Result<Output, Failure> == S.Input {
            let subscription = GCDJobSubscription<Key, Output, Failure, S>(subscriber: subscriber, jobs: jobs, queue: queue, jobworker: jobworker, key: key)
            subscriber.receive(subscription: subscription)
        }
        
        typealias Output = Result<Output, Failure>
        typealias Failure = Never
        
        private let jobs: JobMap
        private let queue: DispatchQueue
        private var jobworker: JobWorker<Key, Output, Failure>
        private var key: Key
        init(jobs: JobMap, queue: DispatchQueue, jobworker: @escaping JobWorker<Key, Output, Failure>, key: Key) {
            self.jobs = jobs
            self.queue = queue
            self.jobworker = jobworker
            self.key = key
        }
        
        func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Result<Output, Failure> == S.Input {
            
        }
    }
    private class GCDJobSubscription<Key: Hashable, Output, Failure: Error,S: Subscriber>: Subscription where S.Input == Result<Output, Failure>, S.Failure == Never {
        func cancel() {
            subscriber = nil
        }
        
        private var subscriber: S?
        public var jobs: JobMap
        private var queue: DispatchQueue
        private var jobworker: JobWorker<Key, Output, Failure>
        private var key: Key
        init(subscriber: S, jobs: JobMap, queue: DispatchQueue, jobworker: @escaping JobWorker<Key, Output, Failure>, key: Key) {
            self.subscriber = subscriber
            self.jobs = jobs
            self.queue = queue
            self.jobworker = jobworker
            self.key = key
        }
        
        func request(_ demand: Subscribers.Demand) {
            for i in jobs.keys {
                queue.async {
                    _ = self.jobs[i]
                    self.jobworker(self.key){result in
                        switch result {
                        case .success(_):
                            _ = self.subscriber?.receive(result)
                        case .failure(let error):
                            print(error.localizedDescription)
                        }
                        
                    }
                }
            }
            
            func cancel() {
                subscriber = nil
            }
        }
    }
    public func startJob(for key: Key) -> AnyPublisher<Result<Output, Failure>, Never> {
        if memOptions.contains(.started) {
            if jobmap.keys.contains(key){
                return jobmap[key]!
            }else{
                let newJobPublisher = GCDJobPublisher(jobs: jobmap, queue: backgroundQ, jobworker: jobworker, key: key)
                jobmap[key] = AnyPublisher<Result<Output, Failure>, Never>(newJobPublisher)
                return newJobPublisher.eraseToAnyPublisher()
            }
        }else{
            let newJobPublisher = GCDJobPublisher(jobs: jobmap, queue: backgroundQ, jobworker: jobworker, key: key)
            return newJobPublisher.eraseToAnyPublisher()
        }
    }
}
