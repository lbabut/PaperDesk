# Download statistics

The persistent SQLite database is `/var/lib/paperdesk/stats.sqlite3` on production.
It stores daily totals by archive filename and ISO country code, not visitor IPs
or identities. The public `/api/download-countries` endpoint exposes only all-time
country totals; `/api/download-count` exposes their combined total. These are
download requests successfully written by the server, not unique people or proof
that a browser saved a file. HEAD, checksums and missing files do not count.

Existing downloads are migrated once into `legacy`, country `ZZ` (unknown).
Deployments preserve the database. Statistics start by country at this release;
historical countries cannot be reconstructed from the old counter.

Caddy overwrites `X-PaperDesk-Client-IP` with the connection's remote address.
The backend accepts it only from loopback. Keep the backend bound to loopback.
If adding a CDN, configure and validate its trusted proxy addresses first.
The application request logger does not record IPs; geolocation is offline.

Country data: [DB-IP Lite](https://db-ip.com/db/download/ip-to-country-lite),
September 2026, CC BY 4.0. Map boundaries: Natural Earth, public domain.
The country database lives outside the web root; no visitor IP is sent to DB-IP.
The website attributes both providers in its map dialog. Country results are
approximate and VPNs can change them.

Before deploying, download the current official DB-IP Lite CSV gzip into
`deploy/geoip/dbip-country-lite.csv.gz`; validate its CSV and ordered ranges using
`website/geoip.py`. The deployment script installs it into `/var/lib/paperdesk`.
Refresh it periodically from DB-IP; deployments do not download it automatically.

Administrator SQL report (through SSH, not a public administration endpoint):

```sql
SELECT day, artifact, country, downloads
FROM download_countries ORDER BY day DESC, downloads DESC;
```
