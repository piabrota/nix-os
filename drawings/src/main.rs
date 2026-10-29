//! `mu-art`: writes docs/drawings/mu.svg and its Desmos state, docs/drawings/mu.desmos.json.
//!
//! ```console
//! cargo run -q --manifest-path drawings/Cargo.toml > docs/drawings/mu.svg
//! cargo run -q --manifest-path drawings/Cargo.toml -- desmos > docs/drawings/mu.desmos.json
//! cargo run -q --manifest-path drawings/Cargo.toml -- check > /tmp/mu-check.svg   # to look at
//! ```

mod mu;
mod pen;

fn main() -> Result<(), String> {
    let art = mu::drawing();
    let out = match std::env::args().nth(1).as_deref() {
        Some("desmos") => serde_json::to_string_pretty(&art.desmos()).map_err(|e| e.to_string())?,
        Some("check") => art.check_svg()?,
        None => art.svg(),
        Some(other) => {
            return Err(format!(
                "unknown argument {other}: try `desmos`, `check` or nothing"
            ))
        }
    };
    println!("{out}");
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn the_committed_files_are_the_output() {
        let art = super::mu::drawing();
        let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/../docs/drawings/");
        let svg = std::fs::read_to_string(format!("{dir}mu.svg")).expect("mu.svg");
        let json = std::fs::read_to_string(format!("{dir}mu.desmos.json")).expect("mu.desmos.json");
        assert_eq!(svg, art.svg() + "\n", "run `just drawing`");
        assert_eq!(
            json,
            serde_json::to_string_pretty(&art.desmos()).expect("json") + "\n",
            "run `just drawing`"
        );
    }

    #[test]
    fn the_desmos_file_is_the_drawing() {
        let worst = super::mu::drawing()
            .check()
            .expect("every expression reads back");
        assert!(worst < 0.01, "an expression strays {worst} from its line");
    }
}
