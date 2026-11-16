package piabrota.scripts

import java.nio.charset.StandardCharsets.UTF_8

import piabrota.lib.Sh

/** A GitHub App that asks GitHub's API through curl with its JWT. Used by hermes-github-token,
  * marola-bot-token and tyler-durden-token.
  */
final case class GithubApp(jwt: String):
  /** `curl -fsS --max-time 20` on the API with the JWT, or with `auth` instead; None if it fails. */
  def api(url: String, auth: String = s"Bearer $jwt", post: Option[String] = None): Option[ujson.Value] =
    val cmd = Seq("curl", "-fsS", "--max-time", "20", "-H", GithubApi.accept) ++
      post.toSeq.flatMap(_ => Seq("-X", "POST")) ++ Seq("-H", s"Authorization: $auth") ++
      post.toSeq.flatMap(body => Seq("-d", body)) :+ url
    val r = Sh.call(cmd)
    System.err.print(r.err.text())
    Option.when(r.exitCode == 0)(Jq.parse(r.out.text())).flatten

  /** The installations of the App: `GET /app/installations`. */
  def installations(): Option[List[Installation]] = api(GithubApi.installations).map(Installation.parseList)

  /** A token of one hour for installation `id`, with what `request` asks for (`jq -er .token`). */
  def mint(id: String, request: TokenRequest): Option[String] =
    api(GithubApi.accessTokens(id), post = Some(request.render)).flatMap(Jq.field(_, "token"))

  /** The App's bot user. Its slug and id are "" when a call fails, as `jq -r` left them. */
  def identity(token: String): BotIdentity =
    val slug = api(GithubApi.app).map(v => Jq.rawField(v, "slug")).getOrElse("")
    BotIdentity(slug, api(GithubApi.botUser(slug), auth = s"token $token").map(v => Jq.rawField(v, "id")).getOrElse(""))

object GithubApp:
  /** The App of the credential file `file`, with a JWT signed now. The key exists on disk only while
    * it signs.
    */
  def load(file: os.Path): GithubApp =
    val credential = AppCredential.parse(os.read(file))
    val unsigned = Jwt.unsigned(credential.id, java.time.Instant.now().getEpochSecond)
    GithubApp(Jwt.signed(unsigned, sign(credential.pem, unsigned)))

  /** The RS256 signature by openssl; empty when the key is missing or broken, and GitHub then
    * refuses the JWT, which the caller reports.
    */
  private def sign(pem: Array[Byte], data: String): Array[Byte] =
    val key = os.temp(pem, prefix = "app-key", perms = Mode.OwnerOnly.perms)
    try
      val r = Sh.call("openssl", "dgst", "-sha256", "-sign", key)(using Sh.Opts(stdin = data.getBytes(UTF_8)))
      System.err.print(r.err.text())
      if r.exitCode == 0 then r.out.bytes else Array.emptyByteArray
    finally os.remove(key)
