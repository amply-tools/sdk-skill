# Building a Mini-app over MCP

A **Mini-app** is a screen Amply draws over the app — a bottom sheet, a centred card, a full
screen, a story, or a flow of several — built from Amply Studio's components and shown by a
campaign (Amply SDK **0.12.0+**). With the Amply MCP connected you can build one from a plain
description, publish it and attach it to a draft campaign without opening the admin.

This page is the *how and why*. The exact vocabulary — every component, property, colour token and
action — lives on the server, in the MCP resource **`amply://mini-app/authoring-reference`**. Read it
before your first `mini_app_create` in a session; if it and this page ever disagree, the server is
right.

## The pipeline

1. **Pick the project** — `projects_list`. A mini-app belongs to one project and can only be shown by
   that project's campaigns.
2. **Restate the brief in one line** before building: surface, what it says, what each button does.
   ("A bottom sheet offering 50% off Pro, *See plans* opens a full-screen plan picker, *Not now*
   closes.") In interactive mode let the user correct it; in autopilot just build what was asked.
3. **`mini_app_create`** with a `spec`. The server compiles it into a Studio document and refuses an
   invalid spec with **every** problem listed by path (`screens[1].children[2].on_tap[0]: …`). Fix
   them all and call again — nothing is saved until the spec is valid.
4. **Read `warnings`.** They are not errors, but each one is something the user would notice (an
   image with no height, a language with missing copy, a call to action that is not pinned).
5. **Show the user `editor_url`.** It opens the mini-app in Amply Studio, where they can see it on a
   phone canvas and tweak anything by hand. There is no screenshot tool — say so rather than
   describing what it "looks like".
6. **`mini_app_publish`** freezes the current draft into a version and returns `campaign_content`.
   Publishing an unchanged draft returns the existing version.
7. **`campaign_create`** with `type: "miniApp"` and that `content` — still a **draft**.
8. **`campaign_activate`** is the only step that puts it in front of users. Never take it without the
   user's explicit go-ahead, and only after they have seen the mini-app.

Editing later: `mini_app_get` → change → `mini_app_update` (with the `expected_version` you just read)
→ `mini_app_publish` again → **point the campaign at the new version** (`campaign_update` with the
new `content`). A campaign keeps showing the exact version it was given; publishing alone changes
nothing on devices. `campaign_update` returns the campaign to Draft, so it needs activating again.

## Which surface

| The ask | Surface | Why |
|---|---|---|
| "A screen", "экран", a settings or plan page | **fullscreen** | Say *screen* and the user means the whole screen; reach for a sheet only when they say sheet, popup, "шторка" or "снизу". |
| One offer, one question, one announcement | **sheet** | Rises over the app, the app stays visible behind it; dismissable. Sizes to its content. |
| A yes/no moment — rate us, confirm, a short notice | **card** (centred) | Smallest interruption; reads as a dialog. |
| Several beats told in sequence — release highlights, a feature tour, a promo | **story** | Consecutive story screens play as one story with progress bars, auto-advance, tap to step, ✕ to close. |
| A real flow — onboarding, a plan picker, a multi-step survey | **fullscreen** screens linked with `navigate` | Room for an illustration, copy and pinned buttons; Back works. |
| Collecting answers | any surface + inputs (`choice`, `text_input`, `toggle`, `slider`) bound to a `property`, and a `save_answers` action | Answers become Custom Properties on the device — targetable by later campaigns. |

Surfaces mix: a sheet whose button navigates to a full-screen screen is a normal pattern (the
sheet grows into the screen).

## Making it look good

The defaults already follow the app-style starters (pill buttons, the type ramp, safe areas, a close
affordance). What still decides the result:

- **Brand colour first.** Set `colors.primary` to the app's brand; every button and accent follows,
  and the text on it is picked for contrast unless you set `onPrimary` yourself. A single value is
  used in **both** themes — give `{ "light": …, "dark": … }` for anything that should follow dark
  mode (backgrounds especially), and prefer palette tokens (`@primary`, `@onSurfaceVariant`, …) over
  raw hex in components.
- **One primary action, last.** The filled button is the last element. A secondary choice goes
  directly above it as a toned button (`background: "@surfaceVariant"`, `text_color: "@onSurface"`)
  or as a plain text link — never two filled buttons.
- **Always a way out.** A sheet or card gets a ✕ (a `text` "✕" aligned to the trailing edge with a
  `close` action) or a *Not now* link. Stories draw their own ✕.
- **Sheets and cards size to their content** — nothing in them may grow (`scroll`, an unsized
  `spacer`). The server refuses that, because on a device it collapses to nothing.
- **Full screens pin the call to action** by putting the content in a `scroll` and the buttons after
  it: the scroll takes the free space, the buttons sit on the bottom edge, long copy scrolls instead
  of pushing them off-screen.
- **Short copy.** A headline (`title1`) and one or two lines of body (`body`, secondary colour). On
  stories, white copy over a backdrop; keep it to the lower third.
- **Images:** draw icons and illustrations as inline SVG (the server checks it — shapes, paths,
  gradients; no scripts, no external references, no CSS `style`). For a photo or a logo file, import
  it with `mini_app_image_import` (https URL) and use the returned source. Give every image a
  `height`. A plain web URL is refused: it would not load on the device.
- **Languages:** declare `languages` and give each text as `{ "en": "…", "de": "…" }`. The device
  picks its locale and falls back to the primary language.

## What a mini-app cannot do

Plan around these up front instead of discovering them mid-build — and tell the user which one
their request runs into, with the workaround you chose:

- **No input validation or required fields.** A button always runs its actions. When a value must
  exist, use a choice or a slider (always has a value), or hand off to a native screen with
  `open_link`.
- **Events carry fixed parameters.** `track_event` cannot include what the user typed or picked;
  `save_answers` is how answers reach the device (as Custom Properties).
- **No "set property" on a tap.** To record a choice made by tapping, use a `choice` +
  `save_answers`, or put the value in a `track_event` parameter on that button.
- **A text cannot show an earlier answer.** One confirmation screen per option is the workaround
  for "show them what they picked".
- **No conditions.** Every user sees the same screens; branching is navigation chosen by the user.

## Buttons and actions

- Actions run in order and **`navigate`, `back` and `close` end the list** — anything after them never
  runs. So: `save_answers` → `close`; `open_link` → `close`; `request_review` → `close`;
  `track_event` → `navigate`. The server refuses the wrong order.
- `track_event` sends an event through the SDK under the name you give it — use the app's
  `PascalCase` event naming, and reuse an event the campaigns already target where it fits.
- `open_link` delivers the link to the app's deeplink listener: the right way to hand off to a native
  screen (checkout, settings) that Studio can't draw.
- `request_review` asks the store's native review dialog; the store decides whether it appears.

## Editing an existing mini-app

`mini_app_get` returns the spec with an `id` on every screen, component and choice option — including
mini-apps built by hand in the admin. Send back only what changes:

- A node with an `id` is **patched**: properties you send are set, `null` removes one, properties you
  leave out keep their stored value.
- A `children` (or `options`) list you send is the complete list — members you leave out are deleted.
  Leave the list out to keep it.
- `screens` is always the complete ordered list; `{ "id": "…" }` alone keeps a screen untouched.
- Parts the vocabulary can't express come back as `{ "type": "keep", … }` — send them back unchanged.

`expected_version` must be the version you read; if someone saved in the admin since, the update is
refused — read again and re-apply your change.

## Traps

- A campaign shows the **version it was given**. After editing and publishing, re-point the campaign,
  or devices keep showing the old one.
- Mini-app campaigns only reach devices on **Amply SDK 0.12.0+**; older devices skip them silently.
- Answer `property` keys are `snake_case` and must be unique across the mini-app — they become Custom
  Property keys.
- A mini-app needs the plan's mini-app feature; without it the tools refuse with a plan message.
- There is no delete tool. A mini-app created by mistake stays in the project's Studio list until
  someone removes it in the admin — get the brief right before the first create.
