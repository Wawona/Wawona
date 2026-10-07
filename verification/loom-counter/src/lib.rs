#[cfg(loom)]
include!("../../../src/core/generation_counter.rs");

#[cfg(all(test, loom))]
mod tests {
    use super::GenerationCounter;
    use std::sync::Arc;

    #[test]
    fn two_threads_observe_distinct_bumps() {
        loom::model(|| {
            let counter = Arc::new(GenerationCounter::new());
            let left = Arc::clone(&counter);
            let right = Arc::clone(&counter);
            let t1 = loom::thread::spawn(move || left.bump());
            let t2 = loom::thread::spawn(move || right.bump());
            let a = t1.join().unwrap();
            let b = t2.join().unwrap();
            assert_ne!(a, b);
            assert!(a == 0 || a == 1);
            assert!(b == 0 || b == 1);
            assert_eq!(counter.load(), 2);
        });
    }
}
