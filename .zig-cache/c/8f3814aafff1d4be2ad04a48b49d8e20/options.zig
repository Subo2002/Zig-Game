pub const @"builtin.OptimizeMode" = enum (u2) {
    Debug = 0,
    ReleaseSafe = 1,
    ReleaseFast = 2,
    ReleaseSmall = 3,
};
pub const optimize: @"builtin.OptimizeMode" = .ReleaseFast;
pub const enable_cross_platform_determinism: bool = true;
