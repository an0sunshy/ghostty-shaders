# Security Policy

## Supported versions

Security fixes are applied to the latest release only. There are no backport
branches.

## Threat surface

ghostty-weather is a personal terminal-theming tool. Its attack surface is
narrow and worth naming honestly:

**LaunchAgent (macOS only).** Installing the poller installs a `launchd`
LaunchAgent plist under `~/Library/LaunchAgents/`. The agent runs as the
current user, not root. The plist can be inspected and removed with
`ghostty-weather-poll --uninstall` or manually via `launchctl`.

**Outbound HTTPS to Open-Meteo.** The poller makes one HTTPS request per
15-minute poll to `https://api.open-meteo.com`. No authentication header or
user-identifying token is sent — only the configured latitude/longitude (or
geocoded coordinates) and the requested weather fields. Open-Meteo is a
free, open-data service. If the request fails the previous scene is kept;
there is no retry storm.

**Privacy — location data.** If `LAT`/`LON` are set directly in
`~/.config/ghostty-weather/config.env`, those coordinates go only to
Open-Meteo and nowhere else; no third-party location service is ever
contacted. If a city name or US ZIP is configured instead, it is geocoded a
single time via Open-Meteo's geocoding endpoint and the resulting coordinates
are written to `~/.config/ghostty-weather/location.json`; all subsequent
polls reuse that cached value without further network calls.

**No secrets or API keys.** The tool stores no credentials. `config.env`
holds only lat/lon or a city name and optional behavior flags (e.g.
`PAUSE_ON_BATTERY`).

**File writes.** The daemon writes only to two directories owned by the
current user:

- `~/Library/Caches/ghostty-weather/` — versioned shader files (the 10 most
  recent copies of each scene, rotated automatically).
- `~/.config/ghostty-weather/` — `config.env`, `location.json`, and a small
  `state` file tracking the active scene and pause status.

**Process signaling.** The swap step sends `SIGUSR2` to the Ghostty process
owned by the same user to trigger a config reload. No privileged signal or
cross-user signal is involved.

**Shader compilation.** Ghostty compiles the GLSL shader in its own renderer
process. A malformed or malicious shader would be rejected by the driver; if
compilation fails, `ghostty-weather-swap` detects the error in Ghostty's log
and reverts to the previous shader automatically.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security reports. Send a
private email to [an0sunshy@outlook.com](mailto:an0sunshy@outlook.com) with
a description of the issue and, if possible, steps to reproduce. Given this
is a personal project, responses are best-effort but the goal is to
acknowledge within a few days and address genuine vulnerabilities promptly.
