// Generates the fixture parser and links the test targets against it
// through `galley::build_helper` (no checkout needed: the crate ships
// the generator and compile inputs; contributors can also point
// GALLEY_CHECKOUT at a checkout).

fn main() {
    let _layout = galley::build_helper::generate_and_link(".");
}
