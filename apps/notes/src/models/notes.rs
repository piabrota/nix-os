use sea_orm::entity::prelude::*;

pub use super::_entities::notes::{ActiveModel, Entity, Model};

#[async_trait::async_trait]
impl ActiveModelBehavior for ActiveModel {
    /// Loco's migration gives `created_at` and `updated_at` defaults on insert; an update
    /// stamps `updated_at` here, unless the caller set it.
    async fn before_save<C>(mut self, _db: &C, insert: bool) -> Result<Self, DbErr>
    where
        C: ConnectionTrait,
    {
        if !insert && self.updated_at.is_unchanged() {
            self.updated_at = sea_orm::ActiveValue::Set(chrono::Utc::now().into());
        }
        Ok(self)
    }
}
