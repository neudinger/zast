//! Shared pointer-mutability policy for borrowed declaration constructors.
//!
//! Constructors retain responsibility for allocation and field-slice coercion.
//! This internal helper is not exported by `@import("zast")`; sibling generator
//! files use `const InitResult = @import("InitResult.zig").InitResult;`.

/// Select constructor pointer mutability from the input type.
///
/// - Literal `null` selects `*Descriptor`.
/// - Every other input type selects `*const Descriptor`.
///
/// Slice coercion in the constructor rejects incompatible types; this helper
/// explicitly rejects only untyped `undefined`.
///
/// ### Ownership
///
/// Constness is shallow: borrowed storage may still change through another
/// alias. Typed `undefined` storage remains invalid and cannot be detected here.
///
/// ### Example
///
/// This helper only returns types; it does not allocate a descriptor:
///
/// ```zig
/// const Descriptor = struct {};
/// const Field = struct { name: []const u8 };
/// const Mutable = InitResult(Descriptor, @TypeOf(null));
/// const ReadOnly = InitResult(Descriptor, []const Field);
/// const FixedArray = InitResult(Descriptor, *const [2]Field);
/// ```
///
/// ### Expected output
///
/// No runtime output is produced. `Mutable` is `*Descriptor`; `ReadOnly` and
/// `FixedArray` are both `*const Descriptor`. An optional slice type also selects
/// a const pointer here, but the constructor still rejects it as a slice argument.
pub fn InitResult(comptime Descriptor: type, comptime Input: type) type {
    if (Input == @TypeOf(undefined))
        @compileError("Use null or a slice for initialization, not undefined");
    return if (Input == @TypeOf(null)) *Descriptor else *const Descriptor;
}
