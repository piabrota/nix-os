package piabrota.feeds

/** The answers of the old Python tests (hermes/feeds/tests/fixtures/), here because the Nix build
  * sees only .scala files.
  */
object Fixtures:
  val Rss: String = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Fixture RSS</title>
    <link>https://example.org/</link>
    <item>
      <title>Oh-my-pi &amp; omp: release notes</title>
      <link>https://Example.org/posts/omp-1/?utm_source=rss&amp;id=7#top</link>
      <guid>omp-1</guid>
      <pubDate>Wed, 04 Nov 2026 06:00:00 GMT</pubDate>
      <description><![CDATA[<p>Short <b>teaser</b> &amp; more.</p>]]></description>
    </item>
    <item>
      <title>A complicated story</title>
      <link>https://example.org/posts/story</link>
      <pubDate>Mon, 02 Nov 2026 12:00:00 +0000</pubDate>
      <content:encoded><![CDATA[<p>The <b>Rust</b> port, in <i>full</i>.</p>]]></content:encoded>
    </item>
    <item>
      <title>An item with no link</title>
      <pubDate>Mon, 02 Nov 2026 12:00:00 +0000</pubDate>
      <description>Dropped.</description>
    </item>
    <item>
      <title>An item with no date</title>
      <link>https://example.org/posts/undated</link>
      <description>No date here.</description>
    </item>
  </channel>
</rss>
"""

  val Atom: String = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Fixture releases</title>
  <id>tag:example.org,2026:feed</id>
  <updated>2026-11-04T10:00:00Z</updated>
  <entry>
    <id>tag:example.org,2026:v1.2.0</id>
    <updated>2026-11-03T12:00:00Z</updated>
    <link rel="self" href="https://example.org/self"/>
    <link rel="alternate" type="text/html" href="https://example.org/releases/v1.2.0"/>
    <title>v1.2.0</title>
    <content type="html">&lt;p&gt;Fixes &amp;amp; adds Nix flake support.&lt;/p&gt;</content>
  </entry>
  <entry>
    <id>tag:example.org,2026:v1.1.0</id>
    <published>2026-10-01T08:30:00+02:00</published>
    <link href="https://example.org/releases/v1.1.0"/>
    <title>v1.1.0</title>
    <summary>Plain summary.</summary>
  </entry>
</feed>
"""

  val PodcastCut: String = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Fixture podcast</title>
    <link>https://podcast.example.org/</link>
    <item>
      <title>Episode 3: omp in practice</title>
      <link>https://podcast.example.org/ep3</link>
      <pubDate>Tue, 03 Nov 2026 09:00:00 GMT</pubDate>
      <description>Three.</description>
      <itunes:duration>3600</itunes:duration>
    </item>
    <item>
      <title>Episode 2</title>
      <link>https://podcast.example.org/ep2</link>
      <pubDate>Tue, 27 Oct 2026 09:00:00 GMT</pubDate>
      <description>Two.</description>
    </item>
    <item>
      <title>Episode 1</title>
      <link>https://podcast.example.org/ep1</link>
      <pubDate>Tue, 20 Oct 2026 09:00:00 GMT</pubDate>
      <description>One.</description>
    </item>
    <item>
      <title>Episode 0, cut in the mid
"""

  val Github: String = """{"total_count":3,"items":[{"full_name":"acme/omp-tools","html_url":"https://github.com/acme/omp-tools","description":"Tools for omp <b>users</b>","created_at":"2026-11-02T08:00:00Z","stargazers_count":99},{"full_name":"acme/quiet","html_url":"https://github.com/acme/quiet","description":null,"created_at":"2026-11-01T08:00:00Z","stargazers_count":0},{"full_name":"acme/big","html_url":"https://github.com/acme/big","description":"A big one","created_at":"2026-10-30T08:00:00Z","stargazers_count":100000}]}"""

  val Apple: String = """{"feed":{"title":"Top Podcasts","results":[{"artistName":"Acme Labs","name":"Agents Weekly","releaseDate":"2026-11-03","genres":[{"genreId":"1318","name":"Technology"},{"genreId":"26","name":"Podcasts"}],"url":"https://podcasts.apple.com/us/podcast/agents-weekly/id1"},{"artistName":"Jane Roe","name":"True Crime Hour","releaseDate":"2026-11-03","genres":[{"genreId":"1488","name":"True Crime"},{"genreId":"26","name":"Podcasts"}],"url":"https://podcasts.apple.com/us/podcast/true-crime-hour/id2"},{"artistName":"No Genre","name":"Bare","releaseDate":"2026-11-03","url":"https://podcasts.apple.com/us/podcast/bare/id3"}]}}"""
