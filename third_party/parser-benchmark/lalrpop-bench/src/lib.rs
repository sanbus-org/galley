use std::slice;
use std::str;

use lalrpop_util::lalrpop_mod;

lalrpop_mod!(pub json);
pub mod nom_json;

#[no_mangle]
pub extern "C" fn benchmark_lalrpop(input_ptr: *const u8, input_len: usize) -> bool {
    let bytes = unsafe { slice::from_raw_parts(input_ptr, input_len) };
    
    let s = match str::from_utf8(bytes) {
        Ok(s) => s,
        Err(_) => return false,
    };
    
    let parser = json::JSONParser::new();
    parser.parse(s).is_ok()
}

#[no_mangle]
pub extern "C" fn benchmark_nom(input_ptr: *const u8, input_len: usize) -> bool {
    let bytes = unsafe { slice::from_raw_parts(input_ptr, input_len) };
    
    let s = match str::from_utf8(bytes) {
        Ok(s) => s,
        Err(_) => return false,
    };
    
    nom_json::root::<()>(s).is_ok()
}
