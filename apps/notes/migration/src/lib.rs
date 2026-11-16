//! The migrations of the `notes` app, in the order SeaORM runs them.
pub use sea_orm_migration::prelude::*;

mod m20261030_034745_notes;

/// Lists the migrations, oldest first. A new migration module goes into `migrations()`.
pub struct Migrator;

#[async_trait::async_trait]
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![Box::new(m20261030_034745_notes::Migration)]
    }
}
