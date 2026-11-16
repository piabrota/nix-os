//! The music on the box: a shuffled deck of files, read again from the directory each time it
//! runs out, so a file copied in is played from the next round on, with no restart.
use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
};

const EXTENSIONS: &[&str] = &["mp3", "flac", "ogg", "oga", "opus", "wav"];

/// The tab-separated file in the music directory: a file name, a tab, the credit the licence
/// asks for (artist, title, licence, link). A track without a row is credited by its name.
pub const CREDITS: &str = "credits.tsv";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Track {
    pub path: PathBuf,
    pub name: String,
    pub credit: Option<String>,
}

pub struct Deck {
    dir: PathBuf,
    cards: Vec<Track>,
}

impl Deck {
    pub fn new(dir: PathBuf) -> Self {
        Self {
            dir,
            cards: Vec::new(),
        }
    }

    /// The next track, or `None` when the directory has no playable file.
    pub fn next(&mut self) -> Option<Track> {
        if self.cards.is_empty() {
            self.cards = scan(&self.dir);
            fastrand::shuffle(&mut self.cards);
        }
        self.cards.pop()
    }
}

pub fn scan(dir: &Path) -> Vec<Track> {
    let credits = fs::read_to_string(dir.join(CREDITS))
        .map(|text| parse_credits(&text))
        .unwrap_or_default();
    let Ok(entries) = fs::read_dir(dir) else {
        tracing::warn!(dir = %dir.display(), "cannot read the music directory");
        return Vec::new();
    };
    let mut tracks: Vec<Track> = entries
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.is_file() && playable(p))
        .map(|path| {
            let file = path
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned();
            let name = path
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned();
            let credit = credits.get(&file).cloned();
            Track { path, name, credit }
        })
        .collect();
    tracks.sort_by(|a, b| a.path.cmp(&b.path));
    tracks
}

fn playable(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
}

pub fn parse_credits(text: &str) -> HashMap<String, String> {
    text.lines()
        .filter(|l| !l.trim().is_empty() && !l.starts_with('#'))
        .filter_map(|l| l.split_once('\t'))
        .map(|(file, credit)| (file.trim().to_owned(), credit.trim().to_owned()))
        .filter(|(file, credit)| !file.is_empty() && !credit.is_empty())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("lofi-test-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn credits_skip_comments_blanks_and_rows_without_a_tab() {
        let c =
            parse_credits("# file\tcredit\n\na.mp3\tHoliznaCC0 - Dawn (CC0)\nno tab\nb.ogg\t \n");
        assert_eq!(c.len(), 1);
        assert_eq!(c["a.mp3"], "HoliznaCC0 - Dawn (CC0)");
    }

    #[test]
    fn scan_keeps_audio_files_and_reads_their_credit() {
        let d = dir("scan");
        for f in ["b.MP3", "a.flac", "cover.jpg", CREDITS] {
            fs::write(d.join(f), "").unwrap();
        }
        fs::create_dir(d.join("sub.ogg")).unwrap();
        fs::write(d.join(CREDITS), "a.flac\tSomeone - A (CC BY 4.0)\n").unwrap();
        let t = scan(&d);
        assert_eq!(
            t.iter().map(|t| t.name.as_str()).collect::<Vec<_>>(),
            ["a", "b"]
        );
        assert_eq!(t[0].credit.as_deref(), Some("Someone - A (CC BY 4.0)"));
        assert_eq!(t[1].credit, None);
    }

    #[test]
    fn deck_deals_every_track_once_per_round_then_reads_the_directory_again() {
        let d = dir("deck");
        fs::write(d.join("a.mp3"), "").unwrap();
        fs::write(d.join("b.mp3"), "").unwrap();
        let mut deck = Deck::new(d.clone());
        let mut round: Vec<String> = (0..2).map(|_| deck.next().unwrap().name).collect();
        round.sort();
        assert_eq!(round, ["a", "b"]);
        fs::write(d.join("c.mp3"), "").unwrap();
        let mut next: Vec<String> = (0..3).map(|_| deck.next().unwrap().name).collect();
        next.sort();
        assert_eq!(next, ["a", "b", "c"]);
    }

    #[test]
    fn an_empty_or_missing_directory_deals_nothing() {
        assert_eq!(Deck::new(dir("empty")).next(), None);
        assert_eq!(Deck::new(PathBuf::from("/nonexistent/lofi")).next(), None);
    }
}
