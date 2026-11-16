//! The `notes` binary: Loco's command line (`start`, `db`, `task`) run with this app's hooks and
//! its migrator.
use loco_rs::cli;
use migration::Migrator;
use notes::app::App;

#[tokio::main]
async fn main() -> loco_rs::Result<()> {
    cli::main::<App, Migrator>().await
}
