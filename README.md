# Booru Browser (Godot 4)

Small Godot 4 desktop client that searches public booru JSON APIs and shows a thumbnail grid.

## Sites

- Safebooru
- Gelbooru
- Danbooru
- Rule34

Rating filter is applied as a `rating:` tag when the site supports it. Safebooru defaults to safe.

## Run

1. Install [Godot 4.3+](https://godotengine.org/download).
2. Clone this repo and open the folder as a Godot project.
3. Press F5.

Export as a desktop app from **Project → Export** (Windows / Linux / macOS).

## Notes

- No API keys are bundled. Some hosts (especially Gelbooru) may start requiring a key or block anonymous clients.
- Requests send a simple `User-Agent`. If a site returns 403, change it or add an API key in `scripts/booru_client.gd`.
- Images are downloaded one at a time to stay polite.
- Follow each booru's terms of service. This is a personal client, not a scraper farm.

## Project layout

```
project.godot
scenes/main.tscn
scripts/main.gd
scripts/booru_client.gd
icon.svg
```
