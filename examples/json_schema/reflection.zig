//! Decoded reflection metadata.
//! The decoder owns the storage referenced by slices and pointers.
//! Based on https://raw.githubusercontent.com/google/flatbuffers/master/reflection/reflection.fbs

pub const file_identifier = "BFBS";
pub const file_extension = "bfbs";

pub const BaseType = enum(i8) {
    None = 0,
    UType = 1,
    Bool = 2,
    Byte = 3,
    UByte = 4,
    Short = 5,
    UShort = 6,
    Int = 7,
    UInt = 8,
    Long = 9,
    ULong = 10,
    Float = 11,
    Double = 12,
    String = 13,
    Vector = 14,
    Obj = 15,
    Union = 16,
    Array = 17,
    Vector64 = 18,
    MaxBaseType = 19,
    _,
};

// Bit positions correspond to masks 1, 2, 4, and 8.
pub const AdvancedFeatures = packed struct(u64) {
    advanced_array_features: bool = false,
    advanced_union_features: bool = false,
    optional_scalars: bool = false,
    default_vectors_and_strings: bool = false,
    unknown_bits: u60 = 0,
};

pub const Type = struct {
    base_type: BaseType = .None,
    element: BaseType = .None,
    index: i32 = -1,
    fixed_length: u16 = 0,
    base_size: u32 = 4,
    element_size: u32 = 0,
};

pub const KeyValue = struct {
    key: []const u8,
    value: ?[]const u8 = null,
};

pub const EnumVal = struct {
    name: []const u8,
    value: i64 = 0,

    // Deprecated in reflection.fbs; retained for legacy metadata.
    object: ?*const Object = null,

    union_type: ?*const Type = null,
    documentation: ?[]const []const u8 = null,
    attributes: ?[]const KeyValue = null,
};

pub const Enum = struct {
    name: []const u8,
    values: []const EnumVal,
    is_union: bool = false,
    underlying_type: *const Type,
    attributes: ?[]const KeyValue = null,
    documentation: ?[]const []const u8 = null,
    declaration_file: ?[]const u8 = null,
};

pub const Field = struct {
    name: []const u8,
    type: *const Type,
    id: u16 = 0,
    offset: u16 = 0,
    default_integer: i64 = 0,
    default_real: f64 = 0.0,
    deprecated: bool = false,
    required: bool = false,
    key: bool = false,
    attributes: ?[]const KeyValue = null,
    documentation: ?[]const []const u8 = null,
    optional: bool = false,
    padding: u16 = 0,
    offset64: bool = false,
};

pub const Object = struct {
    name: []const u8,
    fields: []const Field,
    is_struct: bool = false,
    minalign: i32 = 0,
    bytesize: i32 = 0,
    attributes: ?[]const KeyValue = null,
    documentation: ?[]const []const u8 = null,
    declaration_file: ?[]const u8 = null,
};

pub const RPCCall = struct {
    name: []const u8,
    request: *const Object,
    response: *const Object,
    attributes: ?[]const KeyValue = null,
    documentation: ?[]const []const u8 = null,
};

pub const Service = struct {
    name: []const u8,
    calls: ?[]const RPCCall = null,
    attributes: ?[]const KeyValue = null,
    documentation: ?[]const []const u8 = null,
    declaration_file: ?[]const u8 = null,
};

pub const SchemaFile = struct {
    filename: []const u8,
    included_filenames: ?[]const []const u8 = null,
};

pub const Schema = struct {
    objects: []const Object,
    enums: []const Enum,
    file_ident: ?[]const u8 = null,
    file_ext: ?[]const u8 = null,
    root_table: ?*const Object = null,
    services: ?[]const Service = null,
    advanced_features: AdvancedFeatures = .{},
    fbs_files: ?[]const SchemaFile = null,
};
