// Generates the fixture parser and links the test targets against it
// through `galley::build_helper`. Requires GALLEY_CHECKOUT.

fn main() {
    let _layout = galley::build_helper::generate_and_link(".");
}
