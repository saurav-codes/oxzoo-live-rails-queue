# rails-queue (s1)

Deployed with [ox](https://deploywithox.com): deploy a repo to your own server with one command, no Docker. [Docs](https://deploywithox.com/docs) · [Guide for this stack](https://deploywithox.com/docs/guides/rails)

**Live demo:** https://rails-queue.s1.zoo.sorv.dev

> **Role in the zoo:** project `rails-queue` of [oxzoo-live](https://github.com/saurav-codes/oxzoo-live-control/blob/main/zoo/README.md#projects), deployed with [ox](https://deploywithox.com) on server s1 at https://rails-queue.s1.zoo.sorv.dev. The contract it follows is [DESIGN.md](https://github.com/saurav-codes/oxzoo-live-control/blob/main/zoo/DESIGN.md).

Rails 8.1 on Puma with Postgres and a Solid Queue worker. It is the queue
member of the shop-order and ping-pong chains in the zoo (DESIGN.md, P4).

## What it proves

- ox detects a Rails app with no Procfile: Puma start bound to 127.0.0.1:$PORT,
  `/up` health, `bundle install` in deployment mode and `db:prepare` on deploy.
- A second process (`bin/jobs`, Solid Queue) runs as an ox worker from the same
  release, sharing one Postgres database with the web process.
- The Solid Queue schema is created by a normal migration, so `db:prepare` on a
  fresh shared Postgres creates every table. There is no separate queue database.
- No `credentials.yml.enc` and no `master.key`: `SECRET_KEY_BASE` comes from env.
- `POST /webhooks/zoo` verifies zoo-sig v1 (callers mesh-shop and laravel-jobs),
  caps the body at 64 KB, records `webhook-received`, and enqueues a job that
  records `job-done`. For source laravel-jobs the job also POSTs a signed ack to
  `${LARAVEL_URL}/api/acks` and records `ack-sent`.
- `/_zoo/health`, `/_zoo/verify`, `/_zoo/probe`, `/_zoo/trace/:id` per contract.
  The probe does a Postgres round trip, a Solid Queue round trip (job run by the
  worker within 5 s), a worker heartbeat check and a signed verify to laravel-jobs.
  With the worker down the queue and heartbeat checks fail honestly and leave no
  rows or jobs behind.
- `/` shows queue counts, live Solid Queue processes and recent hops.

## ox features

Rails detection, `[workers]`, `build.migrate` (`db:prepare`), shared Postgres
service, `.ruby-version` tool pinning, generated `DATABASE_URL`.

`ox.toml` declares only the worker and Postgres; the puma start and `/up` health
are detected without an `[app]` table (finding 1, fixed in ox d89326bc).

## Variables

| Name | Who | Notes |
|---|---|---|
| PORT, HOST, PUBLIC_URL, PUBLIC_HOST, OX_* | ox | `PUBLIC_HOST` is the only allowed Host in production |
| DATABASE_URL | ox | shared Postgres |
| SECRET_KEY_BASE | you, secret | any long random string |
| WEBHOOK_SECRET | you, secret | same value on mesh-shop and laravel-jobs |
| LARAVEL_URL | you | `https://laravel-jobs.s2.zoo.sorv.dev`, no trailing slash |
| ZOO_PANEL_ORIGIN | you | CORS origin of zoo-control |

## Tests

Needs Ruby 3.4 (brew ruby, not system 2.6) and a local Postgres.

```sh
export PATH=/opt/homebrew/opt/ruby/bin:$PATH
export PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres
bundle install
bin/rails db:prepare RAILS_ENV=test
bin/rails test
```

Recorded run (2026-10-09, Ruby 3.4, Postgres 18.6):

```
20 runs, 77 assertions, 0 failures, 0 errors, 0 skips
```

The tests cover the DESIGN.md signing vectors and fp, every 401 reason, the
64 KB cap, the webhook to trace flow, CORS, and the ack job against a fake
laravel-jobs server.

Also checked by hand in production mode (Puma, `bin/jobs`, fake laravel-jobs):
probe all green, webhook 202 with trace `webhook-received, job-done, ack-sent`,
concurrent probes 200 429 200, bad Host 403, probe with worker stopped fails
only the queue and heartbeat checks.

## ox check

```
ox check . (manifest: ox.toml)

  app.start                  RAILS_ENV=production bundle exec puma -C config/puma.rb -b tcp://127.0.0.1:$PORT detected:config/puma.rb
  app.health                 /up                                                  detected:config/routes.rb
  build.install              bundle config set --local deployment true && bundle config set --local without development:test && bundle install detected:Gemfile.lock
  build.migrate              RAILS_ENV=production bundle exec rails db:prepare    detected:config/application.rb
  workers.jobs               RAILS_ENV=production bin/jobs                        declared
  tools.ruby                 3.4.11                                               detected:.ruby-version
  services.postgres          postgres 18 (shared)                                 default

  Provided by ox: PORT, HOST, OX_ENV, OX_PROJECT, OX_RELEASE, OX_DATA_DIR, PUBLIC_URL, PUBLIC_HOST, DATABASE_URL
  Set on the dashboard before the first deploy: SECRET_KEY_BASE (Rails or Phoenix key base: 128 hex characters, Generate makes it), WEBHOOK_SECRET, LARAVEL_URL, ZOO_PANEL_ORIGIN
  hint: ox.toml has no [app], so the web app detected from config/puma.rb runs next to the workers; if this project serves no web page, set [app] enabled = false

Ready to deploy.
```

## ox findings

1. An `ox.toml` without an `[app]` table drops the detected app: no start, no
   health, no PUBLIC_URL, yet ox check still says "Ready to deploy". Repro:
   this folder with `ox.toml` reduced to `[workers] jobs = "RAILS_ENV=production bin/jobs"`
   and `[services] postgres = {}`, then `ox check .`. Expected: detected app kept.
   Fixed in ox d89326bc; this repo's `ox.toml` now has no `[app]`.
2. The Solid Queue hint above still prints although `[workers] jobs` already
   runs `bin/jobs`. Expected: no hint when a worker runs `bin/jobs`.
   Fixed in ox 92612c79.
