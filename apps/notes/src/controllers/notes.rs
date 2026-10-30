//! The notes pages, server-rendered under `/notes`, behind one password.
//!
//! The password is `NOTES_PASSWORD`, read from the environment file on the box
//! (`/var/lib/loco-secrets/notes.env`), never from the repository. Signing in
//! sets a cookie holding a SHA-256 of `NOTES_SECRET` and the password; every
//! page compares it in constant time. With no password set, the wall stays
//! shut: nobody can sign in.
use axum::{
    extract::{Form, FromRequestParts},
    http::{request::Parts, StatusCode},
    response::Redirect,
};
use axum_extra::extract::cookie::{Cookie, CookieJar, SameSite};
use loco_rs::prelude::*;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::fmt::Write;
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
    Sha256::new()
        .chain_update(secret)
        .chain_update([0])
        .chain_update(password)
        .finalize()
        .iter()
        .fold(String::with_capacity(64), |mut hex, b| {
            let _ = write!(hex, "{b:02x}");
            hex
        })
}

/// Constant-time equality, so a wrong guess takes as long as a near miss.
fn same(given: &str, expected: &str) -> bool {
    given.len() == expected.len() && bool::from(given.as_bytes().ct_eq(expected.as_bytes()))
}

/// In a handler's arguments: the request goes on only with a valid session, and is sent to
/// the sign-in page otherwise.
struct SignedIn;

impl<S: Send + Sync> FromRequestParts<S> for SignedIn {
    type Rejection = Redirect;

    async fn from_request_parts(
        parts: &mut Parts,
        _state: &S,
    ) -> std::result::Result<Self, Self::Rejection> {
        let jar = CookieJar::from_headers(&parts.headers);
        match (password(), jar.get(COOKIE)) {
            (Some(p), Some(c)) if same(c.value(), &token(&p)) => Ok(Self),
            _ => Err(Redirect::to("/notes/login")),
        }
    }
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
    /// The title and the text, trimmed and within the limits, or why not.
    fn checked(&self) -> std::result::Result<(String, String), &'static str> {
        let (title, content) = (self.title.trim(), self.content.trim());
        if title.is_empty() {
            Err("A note needs a title.")
        } else if title.chars().count() > TITLE_MAX || content.chars().count() > CONTENT_MAX {
            Err("That note is too long.")
        } else {
            Ok((title.to_string(), content.to_string()))
        }
    }
}

fn render(
    v: &TeraView,
    status: StatusCode,
    view: &str,
    data: serde_json::Value,
) -> Result<Response> {
    Ok((status, format::render().view(v, view, data)?).into_response())
}

#[debug_handler]
async fn login_form(ViewEngine(v): ViewEngine<TeraView>) -> Result<Response> {
    render(
        &v,
        StatusCode::OK,
        "notes/login.html",
        data!({ "error": false }),
    )
}

#[debug_handler]
async fn login(
    ViewEngine(v): ViewEngine<TeraView>,
    jar: CookieJar,
    Form(form): Form<Login>,
) -> Result<Response> {
    match password() {
        Some(p) if same(&form.password, &p) => {
            let cookie = Cookie::build((COOKIE, token(&p)))
                .path("/notes")
                .http_only(true)
                .secure(true)
                .same_site(SameSite::Lax)
                .max_age(time::Duration::days(7));
            Ok((jar.add(cookie), to_list()).into_response())
        }
        _ => render(
            &v,
            StatusCode::UNAUTHORIZED,
            "notes/login.html",
            data!({ "error": true }),
        ),
    }
}

#[debug_handler]
async fn logout(jar: CookieJar) -> Response {
    (
        jar.remove(Cookie::build(COOKIE).path("/notes")),
        Redirect::to("/notes/login"),
    )
        .into_response()
}

/// The list, newest first, with the form above it. Tera here has no date filter, so the
/// timestamp is formatted before it reaches the view.
async fn list(
    v: &TeraView,
    ctx: &AppContext,
    status: StatusCode,
    error: Option<&str>,
) -> Result<Response> {
    let notes: Vec<_> = Entity::find()
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
    render(
        v,
        status,
        "notes/index.html",
        data!({ "notes": notes, "error": error }),
    )
}

#[debug_handler]
async fn index(
    _: SignedIn,
    ViewEngine(v): ViewEngine<TeraView>,
    State(ctx): State<AppContext>,
) -> Result<Response> {
    list(&v, &ctx, StatusCode::OK, None).await
}

#[debug_handler]
async fn create(
    _: SignedIn,
    ViewEngine(v): ViewEngine<TeraView>,
    State(ctx): State<AppContext>,
    Form(form): Form<NoteForm>,
) -> Result<Response> {
    let (title, content) = match form.checked() {
        Ok(fields) => fields,
        Err(e) => return list(&v, &ctx, StatusCode::UNPROCESSABLE_ENTITY, Some(e)).await,
    };
    ActiveModel {
        title: Set(title),
        content: Set(content),
        ..Default::default()
    }
    .insert(&ctx.db)
    .await?;
    Ok(to_list())
}

#[debug_handler]
async fn edit(
    _: SignedIn,
    ViewEngine(v): ViewEngine<TeraView>,
    State(ctx): State<AppContext>,
    Path(id): Path<i64>,
) -> Result<Response> {
    match Entity::find_by_id(id).one(&ctx.db).await? {
        Some(note) => render(
            &v,
            StatusCode::OK,
            "notes/edit.html",
            data!({ "note": note, "error": null }),
        ),
        None => Ok(to_list()),
    }
}

#[debug_handler]
async fn update(
    _: SignedIn,
    ViewEngine(v): ViewEngine<TeraView>,
    State(ctx): State<AppContext>,
    Path(id): Path<i64>,
    Form(form): Form<NoteForm>,
) -> Result<Response> {
    let Some(note) = Entity::find_by_id(id).one(&ctx.db).await? else {
        return Ok(to_list());
    };
    let (title, content) = match form.checked() {
        Ok(fields) => fields,
        // Show the form again with what was typed, not with what is saved.
        Err(e) => {
            let typed = data!({ "id": id, "title": form.title, "content": form.content });
            return render(
                &v,
                StatusCode::UNPROCESSABLE_ENTITY,
                "notes/edit.html",
                data!({ "note": typed, "error": e }),
            );
        }
    };
    let mut item = note.into_active_model();
    item.title = Set(title);
    item.content = Set(content);
    item.update(&ctx.db).await?;
    Ok(to_list())
}

#[debug_handler]
async fn delete(
    _: SignedIn,
    State(ctx): State<AppContext>,
    Path(id): Path<i64>,
) -> Result<Response> {
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

    fn form(title: &str, content: &str) -> NoteForm {
        NoteForm {
            title: title.into(),
            content: content.into(),
        }
    }

    #[test]
    fn a_note_needs_a_title_and_fits_the_limits() {
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
        assert!(same("abc", "abc"));
        assert!(!same("abc", "abd"));
        assert!(!same("abc", "abcd"));
        assert!(!same("", "abc"));
    }

    #[test]
    fn the_token_depends_on_secret_and_password() {
        assert_ne!(token("one"), token("two"));
        assert_eq!(token("one").len(), 64);
    }
}
