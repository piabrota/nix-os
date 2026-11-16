//! Creates the `notes` table. Loco's `create_table` adds `created_at` and `updated_at` to the
//! columns listed here.
use loco_rs::schema::*;
use sea_orm_migration::prelude::*;

/// `up` creates the table; `down` drops it, and the notes in it.
#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, m: &SchemaManager) -> Result<(), DbErr> {
        create_table(
            m,
            "notes",
            &[
                ("id", ColType::PkAuto),
                ("title", ColType::String),
                ("content", ColType::Text),
            ],
            &[],
        )
        .await
    }

    async fn down(&self, m: &SchemaManager) -> Result<(), DbErr> {
        drop_table(m, "notes").await
    }
}
