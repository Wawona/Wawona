#![no_main]

use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if data.len() < 24 {
        return;
    }
    let mut nums = [0i32; 6];
    for (index, slot) in nums.iter_mut().enumerate() {
        let start = index * 4;
        let bytes: [u8; 4] = data[start..start + 4].try_into().unwrap();
        *slot = i32::from_le_bytes(bytes);
    }
    let (x, y, w, h, mw, mh) = (nums[0], nums[1], nums[2], nums[3], nums[4], nums[5]);
    if mw < 0 || mh < 0 || w < 0 || h < 0 {
        return;
    }
    let (cx, cy, cw, ch) = wawona_helpers_check::invariants::clamp_rect(x, y, w, h, mw, mh);
    assert!(cx >= 0 && cy >= 0 && cw >= 0 && ch >= 0);
    assert!(cx <= mw && cy <= mh);
});
