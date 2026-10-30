use async_trait::async_trait;
use axum::{Extension, Router as AxumRouter};
use loco_rs::{
    app::{AppContext, Initializer},
    controller::views::{engines, ViewEngine},
    Result,
};

/// Tera, reading `assets/views/` from the working directory (`share/notes` on the box).
pub struct ViewEngineInitializer;

#[async_trait]
impl Initializer for ViewEngineInitializer {
    fn name(&self) -> String {
        "view-engine".to_string()
    }

    async fn after_routes(&self, router: AxumRouter, _ctx: &AppContext) -> Result<AxumRouter> {
        let tera = engines::TeraView::build()?;
        Ok(router.layer(Extension(ViewEngine::from(tera))))
    }
}
