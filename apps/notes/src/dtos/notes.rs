use sea_orm::prelude::DateTimeWithTimeZone;
use ts_rs::TS;

#[derive(serde::Serialize, serde::Deserialize, TS)]
pub struct NoteDto {
    #[ts(type = "number")]
    pub id: i64,
    pub title: String,
    pub content: String,
    #[ts(type = "string")]
    pub created_at: DateTimeWithTimeZone,
    #[ts(type = "string")]
    pub updated_at: DateTimeWithTimeZone,
}

impl From<crate::models::_entities::notes::Model> for NoteDto {
    fn from(m: crate::models::_entities::notes::Model) -> Self {
        Self {
            id: m.id,
            title: m.title,
            content: m.content,
            created_at: m.created_at,
            updated_at: m.updated_at,
        }
    }
}

#[derive(serde::Serialize, serde::Deserialize, TS)]
pub struct CreateNote {
    pub title: String,
    pub content: String,
}

#[derive(serde::Serialize, serde::Deserialize, TS)]
pub struct UpdateNote {
    pub title: String,
    pub content: String,
}
