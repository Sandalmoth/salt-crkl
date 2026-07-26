pub const block_size = 64 * 1024;

pub const KeyGen = struct {
    counter: u64,
    weyl: u64,

    pub fn init(seed: u32) KeyGen {
        var weyl: u64 = seed;
        weyl = 0xbf07289400000001 | (weyl << 1);
        return .{
            .counter = weyl,
            .weyl = weyl,
        };
    }

    pub fn next(keygen: *KeyGen) u64 {
        var x = @atomicRmw(u64, &keygen.counter, .Add, keygen.weyl, .monotonic);
        // SplitMix64
        x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
        x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
        x ^= (x >> 31);
        return x;
    }
};
