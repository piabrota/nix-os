//! The `notes` app: a small Loco CRUD on SQLite, served under `/notes` (declared in `apps.nix`).
//! `app` holds the Loco hooks, `controllers` the pages, `models` the table, `initializers` the
//! template engine.
pub mod app;
pub mod controllers;
pub mod initializers;
pub mod models;
