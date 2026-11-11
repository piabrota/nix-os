//! lofi: a Discord bot that sits in one voice channel and plays the music files of one directory,
//! shuffled, without end. It joins on start, comes back when it is disconnected, shows the track
//! in its status and answers `/np` with the track and its credit. No message content, no cache.
mod deck;

use std::{
    env,
    num::NonZeroU64,
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    time::Duration,
};

use serenity::{
    all::{
        ActivityData, ChannelId, CommandInteraction, Context, CreateCommand,
        CreateInteractionResponse, CreateInteractionResponseMessage, EventHandler, GatewayIntents,
        GuildId, Interaction, Ready,
    },
    async_trait, Client,
};
use songbird::{
    input::File,
    tracks::{Track, TrackHandle},
    Call, Event, EventContext, EventHandler as VoiceEventHandler, SerenityInit, Songbird,
    TrackEvent,
};
use tokio::sync::{mpsc, Mutex};

/// Tracks queued ahead of the one playing: one file open at a time, the next one ready.
const QUEUE_AHEAD: usize = 2;
const NO_MUSIC_RETRY: Duration = Duration::from_secs(60);
const REJOIN_MAX: Duration = Duration::from_secs(300);

struct Config {
    guild: GuildId,
    channel: ChannelId,
    music: PathBuf,
    volume: f32,
}

impl Config {
    fn from_env() -> Result<Self, String> {
        let id = |name: &str| -> Result<NonZeroU64, String> {
            env::var(name)
                .map_err(|_| format!("{name} is not set"))?
                .trim()
                .parse()
                .map_err(|_| format!("{name} is not a Discord ID"))
        };
        let volume = match env::var("LOFI_VOLUME") {
            Ok(v) => v
                .parse::<f32>()
                .ok()
                .filter(|v| (0.0..=1.0).contains(v))
                .ok_or("LOFI_VOLUME is not a number from 0 to 1")?,
            Err(_) => 0.5,
        };
        Ok(Self {
            guild: GuildId::from(id("LOFI_GUILD_ID")?),
            channel: ChannelId::from(id("LOFI_CHANNEL_ID")?),
            music: env::var("LOFI_MUSIC_DIR")
                .unwrap_or_else(|_| "/var/lib/lofi/music".into())
                .into(),
            volume,
        })
    }
}

enum Msg {
    TopUp,
    Rejoin,
    Playing(TrackHandle),
}

/// Forwards the driver's events to the supervisor, which owns the call.
struct Forward {
    tx: mpsc::UnboundedSender<Msg>,
    on: fn(&EventContext<'_>) -> Option<Msg>,
}

#[async_trait]
impl VoiceEventHandler for Forward {
    async fn act(&self, ctx: &EventContext<'_>) -> Option<Event> {
        if let Some(msg) = (self.on)(ctx) {
            let _ = self.tx.send(msg);
        }
        None
    }
}

struct Handler {
    config: Arc<Config>,
    started: AtomicBool,
    tx: mpsc::UnboundedSender<Msg>,
    rx: Mutex<Option<mpsc::UnboundedReceiver<Msg>>>,
}

#[async_trait]
impl EventHandler for Handler {
    async fn ready(&self, ctx: Context, ready: Ready) {
        tracing::info!(user = %ready.user.name, "connected to the gateway");
        let np = CreateCommand::new("np").description("The track playing now, and its credit");
        if let Err(e) = self.config.guild.set_commands(&ctx.http, vec![np]).await {
            tracing::warn!(error = %e, "cannot register /np");
        }
        if self.started.swap(true, Ordering::SeqCst) {
            // A new gateway session after a long outage: the voice state may be gone.
            let _ = self.tx.send(Msg::Rejoin);
            return;
        }
        let Some(rx) = self.rx.lock().await.take() else {
            return;
        };
        let manager = songbird::get(&ctx).await.expect("songbird is registered");
        tokio::spawn(supervise(
            ctx,
            manager,
            self.config.clone(),
            self.tx.clone(),
            rx,
        ));
    }

    async fn interaction_create(&self, ctx: Context, interaction: Interaction) {
        let Interaction::Command(cmd) = interaction else {
            return;
        };
        if cmd.data.name == "np" {
            now_playing(&ctx, &cmd, self.config.guild).await;
        }
    }
}

async fn now_playing(ctx: &Context, cmd: &CommandInteraction, guild: GuildId) {
    let current = match songbird::get(ctx).await.and_then(|m| m.get(guild)) {
        Some(call) => call.lock().await.queue().current(),
        None => None,
    };
    let text = match current {
        Some(handle) => {
            let t = handle.data::<deck::Track>();
            match &t.credit {
                Some(credit) => format!("🎧 **{}**\n{credit}", t.name),
                None => format!("🎧 **{}**", t.name),
            }
        }
        None => "Nothing is playing.".to_owned(),
    };
    let reply = CreateInteractionResponseMessage::new()
        .content(text)
        .ephemeral(true);
    if let Err(e) = cmd
        .create_response(&ctx.http, CreateInteractionResponse::Message(reply))
        .await
    {
        tracing::warn!(error = %e, "cannot answer /np");
    }
}

/// Owns the voice call: joins, keeps the queue full, rejoins with a growing delay.
async fn supervise(
    ctx: Context,
    manager: Arc<Songbird>,
    config: Arc<Config>,
    tx: mpsc::UnboundedSender<Msg>,
    mut rx: mpsc::UnboundedReceiver<Msg>,
) {
    let mut deck = deck::Deck::new(config.music.clone());
    let mut backoff = Duration::from_secs(5);
    let mut events_added = false;
    let mut call = loop {
        match join(&manager, &config).await {
            Some(call) => break call,
            None => tokio::time::sleep(backoff).await,
        }
        backoff = (backoff * 2).min(REJOIN_MAX);
    };
    loop {
        if !events_added {
            let mut c = call.lock().await;
            let forward = |on| Forward { tx: tx.clone(), on };
            c.add_global_event(Event::Track(TrackEvent::End), forward(|_| Some(Msg::TopUp)));
            c.add_global_event(Event::Track(TrackEvent::Error), forward(on_error));
            c.add_global_event(Event::Track(TrackEvent::Play), forward(on_play));
            c.add_global_event(
                Event::Core(songbird::CoreEvent::DriverDisconnect),
                forward(|_| Some(Msg::Rejoin)),
            );
            events_added = true;
        }
        top_up(&call, &mut deck, &config, &tx).await;
        backoff = Duration::from_secs(5);

        while let Some(msg) = rx.recv().await {
            match msg {
                Msg::TopUp => top_up(&call, &mut deck, &config, &tx).await,
                Msg::Playing(handle) => {
                    let t = handle.data::<deck::Track>();
                    tracing::info!(track = %t.name, "playing");
                    ctx.set_activity(Some(ActivityData::listening(t.name.clone())));
                }
                Msg::Rejoin => break,
            }
        }

        tracing::warn!("voice disconnected, joining again");
        call = loop {
            tokio::time::sleep(backoff).await;
            if let Some(call) = join(&manager, &config).await {
                break call;
            }
            backoff = (backoff * 2).min(REJOIN_MAX);
        };
    }
}

fn on_play(ctx: &EventContext<'_>) -> Option<Msg> {
    match ctx {
        EventContext::Track([(_, handle), ..]) => Some(Msg::Playing((*handle).clone())),
        _ => None,
    }
}

fn on_error(ctx: &EventContext<'_>) -> Option<Msg> {
    if let EventContext::Track(tracks) = ctx {
        for (state, handle) in tracks.iter() {
            let t = handle.data::<deck::Track>();
            tracing::warn!(file = %t.path.display(), state = ?state.playing, "cannot play");
        }
    }
    Some(Msg::TopUp)
}

async fn join(manager: &Songbird, config: &Config) -> Option<Arc<Mutex<Call>>> {
    match manager.join(config.guild, config.channel).await {
        Ok(call) => {
            if let Err(e) = call.lock().await.deafen(true).await {
                tracing::warn!(error = %e, "cannot deafen");
            }
            tracing::info!(channel = %config.channel, "joined the voice channel");
            Some(call)
        }
        Err(e) => {
            tracing::warn!(error = %e, "cannot join the voice channel");
            None
        }
    }
}

async fn top_up(
    call: &Mutex<Call>,
    deck: &mut deck::Deck,
    config: &Config,
    tx: &mpsc::UnboundedSender<Msg>,
) {
    let mut call = call.lock().await;
    while call.queue().len() < QUEUE_AHEAD {
        let Some(t) = deck.next() else {
            tracing::warn!(dir = %config.music.display(), "no music to play, looking again in 60 s");
            let tx = tx.clone();
            tokio::spawn(async move {
                tokio::time::sleep(NO_MUSIC_RETRY).await;
                let _ = tx.send(Msg::TopUp);
            });
            return;
        };
        let input = File::new(t.path.clone()).into();
        call.enqueue(Track::new_with_data(input, Arc::new(t)).volume(config.volume))
            .await;
    }
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "lofi=info,songbird=warn,serenity=warn".into()),
        )
        .without_time() // journald stamps each line
        .init();

    let config = match Config::from_env() {
        Ok(c) => Arc::new(c),
        Err(e) => {
            eprintln!("lofi: {e}");
            std::process::exit(2);
        }
    };
    let token = env::var("DISCORD_TOKEN").unwrap_or_else(|_| {
        eprintln!("lofi: DISCORD_TOKEN is not set");
        std::process::exit(2);
    });

    let (tx, rx) = mpsc::unbounded_channel();
    let handler = Handler {
        config,
        started: AtomicBool::new(false),
        tx,
        rx: Mutex::new(Some(rx)),
    };
    let intents = GatewayIntents::GUILDS | GatewayIntents::GUILD_VOICE_STATES;
    let mut client = Client::builder(&token, intents)
        .event_handler(handler)
        .register_songbird()
        .await
        .expect("cannot build the Discord client");

    let shards = client.shard_manager.clone();
    // systemd stops the unit with SIGTERM: close the gateway so Discord drops the bot from the
    // channel at once, not after its timeout.
    tokio::spawn(async move {
        use tokio::signal::unix::{signal, SignalKind};
        let mut term = signal(SignalKind::terminate()).expect("cannot listen for SIGTERM");
        tokio::select! {
            _ = term.recv() => {}
            _ = tokio::signal::ctrl_c() => {}
        }
        shards.shutdown_all().await;
    });
    if let Err(e) = client.start().await {
        eprintln!("lofi: {e}");
        // A wrong token will not get better by itself: the unit does not restart on 2.
        let unauthorized = matches!(&e, serenity::Error::Http(serenity::http::HttpError::UnsuccessfulRequest(r)) if r.status_code.as_u16() == 401);
        std::process::exit(if unauthorized { 2 } else { 1 });
    }
}
