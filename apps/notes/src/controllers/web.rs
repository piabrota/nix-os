//! The notes pages, server-rendered under `/notes`, behind one password.
//!
//! The password is `NOTES_PASSWORD`, read from the environment file on the box
//! (`/var/lib/loco-secrets/notes.env`), never from the repository. Signing in
//! sets a cookie holding a SHA-256 of `NOTES_SECRET` and the password; every
//! page compares it in constant time. With no password set, the wall stays
//! shut: nobody can sign in.
#![allow(clippy::unused_async)]
use axum::{extract::Form, http::StatusCode, response::Redirect};
use axum_extra::extract::cookie::{Cookie, CookieJar, SameSite};
use loco_rs::prelude::*;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

use crate::models::_entities::notes::{ActiveModel, Column, Entity};

const COOKIE: &str = "notes_session";
const TITLE_MAX: usize = 200;
const CONTENT_MAX: usize = 20_000;

fn password() -> Option<String> {
    std::env::var("NOTES_PASSWORD")
        .ok()
        .filter(|p| !p.is_empty())
}

/// What the cookie holds for a password: hex(SHA-256(secret, 0, password)).
fn token(password: &str) -> String {
    let secret = std::env::var("NOTES_SECRET").unwrap_or_default();
    let mut hash = Sha256::new();
    hash.update(secret.as_bytes());
    hash.update([0u8]);
    hash.update(password.as_bytes());
    hash.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

fn matches(given: &str, expected: &str) -> bool {
    given.len() == expected.len() && bool::from(given.as_bytes().ct_eq(expected.as_bytes()))
}

fn signed_in(jar: &CookieJar) -> bool {
    match (password(), jar.get(COOKIE)) {
        (Some(p), Some(c)) => matches(c.value(), &token(&p)),
        _ => false,
    }
}

fn to_login() -> Response {
    Redirect::to("/notes/login").into_response()
}

fn to_list() -> Response {
    Redirect::to("/notes").into_response()
}

#[derive(Deserialize)]
struct Login {
    password: String,
}

#[derive(Deserialize)]
struct NoteForm {
    title: String,
    content: String,
}

impl NoteForm {
    /// Trimmed and within the limits, or the reason it is not.
    fn checked(self) -> std::result::Result<(String, String), &'static str> {
        let title = self.title.trim().to_string();
        let content = self.content.trim().to_string();
        if title.is_empty() {
            return Err("A note needs a title.");
        }
        if title.chars().count() > TITLE_MAX || content.chars().count() > CONTENT_MAX {
            return Err("That note is too long.");
        }
        Ok((title, content))
    }
}

#[debug_handler]
async fn login_form(ViewEngine(v): ViewEngine<TeraView>) -> Result<Response> {
    format::render().view(&v, "notes/login.html", data!({ "error": false }))
}

#[debug_handler]
async fn login(
    ViewEngine(v): ViewEngine<TeraView>,
    jar: CookieJar,
    Form(form): Form<Login>,
) -> Result<Response> {
    if let Some(p) = password() {
        if matches(&form.password, &p) {
            let cookie = Cookie::build((COOKIE, token(&p)))
                .path("/notes")
                .http_only(true)
                .secure(true)
                .same_site(SameSite::Lax)
                .max_age(time::Duration::days(7));
            return Ok((jar.add(cookie), to_list()).into_response());
        }
    }
    let page = format::render().view(&v, "notes/login.html", data!({ "error": true }))?;
    Ok((StatusCode::UNAUTHORIZED, page).into_response())
}

#[debug_handler]
async fn logout(jar: CookieJar) -> Result<Response> {
    Ok((jar.remove(Cookie::build(COOKIE).path("/notes")), to_login()).into_response())
}

async fn list_page(
    v: &TeraView,
    ctx: &AppContext,
    error: Option<&str>,
    status: StatusCode,
) -> Result<Response> {
    // Tera here has no date filter: the timestamp is formatted before it reaches the view.
    let notes: Vec<serde_json::Value> = Entity::find()
        .order_by_desc(Column::UpdatedAt)
        .all(&ctx.db)
        .await?
        .into_iter()
        .map(|n| {
            serde_json::json!({
                "id": n.id,
                "title": n.title,
                "content": n.content,
                "updated": n.updated_at.format("%Y-%m-%d %H:%M").to_string(),
            })
        })
        .collect();
    let page = format::render().view(
        v,
        "notes/index.html",
        data!({ "notes": notes, "error": error }),
    )?;
    Ok((status, page).into_response())
}

#[debug_handler]
async fn index(
    ViewEngine(v): ViewEngine<TeraView>,
    State(ctx): State<AppContext>,
    jar: CookieJar,
) -> Result<Response> {
    if !signed_in(&jar) {
        return Ok(to_login());
    }
    list_page(&v, &ctx, None, StatusCode::OK).await
}

#[debug_handler]
async fn create(
    ViewEngine(v): ViewEngine<TeraView>,
    State(ctx): State<AppContext>,
    jar: CookieJar,
    Form(form): Form<NoteForm>,
) -> Result<Response> {
    if !signed_in(&jar) {
        return Ok(to_login());
    }
    match form.checked() {
        Ok((title, content)) => {
            ActiveModel {
                title: Set(title),
                content: Set(content),
                ..Default::default()
            }
            .insert(&ctx.db)
            .await?;
            Ok(to_list())
        }
        Err(e) => list_page(&v, &ctx, Some(e), StatusCode::UNPROCESSABLE_ENTITY).await,
    }
}

#[debug_handler]
async fn edit(
    ViewEngine(v): ViewEngine<TeraView>,
    State(ctx): State<AppContext>,
    jar: CookieJar,
    Path(id): Path<i64>,
) -> Result<Response> {
    if !signed_in(&jar) {
        return Ok(to_login());
    }
    let Some(note) = Entity::find_by_id(id).one(&ctx.db).await? else {
        return Ok(to_list());
    };
    format::render().view(
        &v,
        "notes/edit.html",
        data!({ "note": note, "error": null }),
    )
}

#[debug_handler]
async fn update(
    ViewEngine(v): ViewEngine<TeraView>,
    State(ctx): State<AppContext>,
    jar: CookieJar,
    Path(id): Path<i64>,
    Form(form): Form<NoteForm>,
) -> Result<Response> {
    if !signed_in(&jar) {
        return Ok(to_login());
    }
    let Some(note) = Entity::find_by_id(id).one(&ctx.db).await? else {
        return Ok(to_list());
    };
    match form.checked() {
        Ok((title, content)) => {
            let mut item = note.into_active_model();
            item.title = Set(title);
            item.content = Set(content);
            item.update(&ctx.db).await?;
            Ok(to_list())
        }
        Err(e) => {
            let page = format::render().view(
                &v,
                "notes/edit.html",
                data!({ "note": note, "error": e }),
            )?;
            Ok((StatusCode::UNPROCESSABLE_ENTITY, page).into_response())
        }
    }
}

#[debug_handler]
async fn delete(
    State(ctx): State<AppContext>,
    jar: CookieJar,
    Path(id): Path<i64>,
) -> Result<Response> {
    if !signed_in(&jar) {
        return Ok(to_login());
    }
    Entity::delete_by_id(id).exec(&ctx.db).await?;
    Ok(to_list())
}

pub fn routes() -> Routes {
    Routes::new()
        .prefix("notes")
        .add("/", get(index).post(create))
        .add("/login", get(login_form).post(login))
        .add("/logout", post(logout))
        .add("/{id}/edit", get(edit))
        .add("/{id}", post(update))
        .add("/{id}/delete", post(delete))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_note_needs_a_title_and_fits_the_limits() {
        let form = |t: &str, c: &str| NoteForm {
            title: t.into(),
            content: c.into(),
        };
        assert_eq!(
            form("  hi ", " there ").checked(),
            Ok(("hi".into(), "there".into()))
        );
        assert!(form("   ", "x").checked().is_err());
        assert!(form(&"x".repeat(TITLE_MAX + 1), "").checked().is_err());
        assert!(form("t", &"x".repeat(CONTENT_MAX + 1)).checked().is_err());
    }

    #[test]
    fn the_password_check_is_exact() {
        assert!(matches("abc", "abc"));
        assert!(!matches("abc", "abd"));
        assert!(!matches("abc", "abcd"));
        assert!(!matches("", "abc"));
    }

    #[test]
    fn the_token_depends_on_secret_and_password() {
        assert_ne!(token("one"), token("two"));
        assert_eq!(token("one").len(), 64);
    }
}
