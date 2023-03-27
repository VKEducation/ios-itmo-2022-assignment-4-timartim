import XCTest
@testable import JobTracking
enum MyError: Error, Equatable {
    case RunTimeError(String)
}
final class JobTrackingTests: XCTestCase {
    func testGCDFirst() {
        let tracker = GCDJobTracker<String, Int, Error>(memoizing: [.started, .completed], worker: { key, completion in
                DispatchQueue.global().async {
                    let result = Int(key) ?? 0
                    completion(.success(result))
                }
            })

        let key = "123"
        let expectation = XCTestExpectation(description: "Completion should be called")
        tracker.startJob(for: key) { result in
            switch result {
            case .success(let value):
                XCTAssertEqual(value, 123)
            case .failure(_):
                XCTFail("Job should succeed")
            }
            expectation.fulfill()

        }
        wait(for: [expectation], timeout: 1)
    }
    func testAsyncTracker() async throws{
        let memoizationOptions: MemoizationOptions = [.started, .succeeded]
        let jobWorker: JobWorker<Int, String, MyError> = { key, completion in
            completion(.success("Result for key \(key)"))
        }
        let tracker = ConcurrentJobTracker(memoizing: memoizationOptions, worker: jobWorker)
        
        let result1 = try await tracker.startJob(for: 1)
        XCTAssertEqual(result1, "Result for key 1")
        
        let result2 = try await tracker.startJob(for: 2)
        XCTAssertEqual(result2, "Result for key 2")
        
        let result3 = try await tracker.startJob(for: 1)
        XCTAssertEqual(result3, "Result for key 1")
        
        let result4 = try await tracker.startJob(for: 3)
        XCTAssertEqual(result4, "Result for key 3")
        
        let result5 = try await tracker.startJob(for: 2)
        XCTAssertEqual(result5, "Result for key 2")
    }
    func testCombineTracker() {
        let jobTracker = CombineJobTracker<String, Int, MyError>(memoizing: [.started], worker: { key, completion in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    completion(.success(key.count))
                }
            })
        let expectation = XCTestExpectation(description: "Job result received")
        let cancellable = jobTracker.startJob(for: "hello")
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                XCTAssertEqual(result, .success(5))
                expectation.fulfill()
            })
        cancellable.cancel()
    }

}
