import Foundation
public class GCDJobTracker<key: Hashable, Output, Failure:Error >:CallbackJobTracking{
    enum Status{
        case running(awaitingCallbacks: [(Result<Output, Failure>) -> Void])
        case completed(result: Result<Output, Failure>)
    }
    private let memOptions : MemoizationOptions
    private let jobworker : JobWorker<key, Output, Failure>
    private var jobStatus : [key : Status] = [:]
    let backgroundQ = DispatchQueue.global(qos: .utility)
    public required init(memoizing: MemoizationOptions, worker: @escaping JobWorker<key, Output, Failure>) {
        memOptions = memoizing
        jobworker = worker
    }
    
    public typealias Key = key
    
    public typealias Output = Output
    
    public typealias Failure = Failure
    public func startJob(for key: key, completion: @escaping (Result<Output, Failure>) -> Void) {
        if memOptions.contains(.started){
            if jobStatus.keys.contains(key) {
                let waiting = jobStatus[key]
                switch waiting{
                case .running(var arrayOfCompletion):
                    arrayOfCompletion.append(completion)
                case .completed(let result):
                    completion(result)
                default:
                    return
                }
            }else {
                let arrayOfCompletion :[(Result<Output, Failure>) -> Void] = [completion]
                jobStatus[key] = .running(awaitingCallbacks: arrayOfCompletion)
                backgroundQ.async{
                    self.jobworker(key){result in
                        switch(self.jobStatus[key]){
                        case .running(let a):
                            self.jobStatus[key] = .completed(result: result)
                            for task in a{
                                if self.memOptions.contains(.completed){
                                    task(result)
                                }else
                                if(self.memOptions.contains(.failed)){
                                    switch result{
                                    case .failure(_):
                                        task(result)
                                    default:
                                        continue
                                    }
                                }
                                if(self.memOptions.contains(.succeeded)){
                                    switch result{
                                    case .success(_):
                                        task(result)
                                    default:
                                        continue
                                    }
                                }
                                
                                
                            }
                        default:
                            return
                        }
                    }
                }
            }
        }else{
            let arrayOfCompletion :[(Result<Output, Failure>) -> Void] = [completion]
            jobStatus[key] = .running(awaitingCallbacks: arrayOfCompletion)
            backgroundQ.async{
                self.jobworker(key){result in
                    
                }
            }
        }
    }
}
