# Arena RPG plan

## Codebase cleanup
- [x] Nest each spec beneath its tested module and update test commands.
- [x] Nest the client team HUD beneath Capture; name status indicators explicitly.
- [x] Group authored combat audio/highlight pools under Assets/Combat.
- [x] Extract client feedback/animations and server attacks/hits/characters into typed child modules.
- [x] Move keyboard/button dispatch and touch gestures into InputActionController; use native InputActions for discrete bindings.
- [x] Put a concise source map and contribution conventions near the top of README.
- [x] Verify behavior against the current workspace baseline, specs, formatting, and Rojo hierarchy/build.

Review: all seven specs are children of their modules; production require paths and all 30 server Combat methods are preserved. Server Combat now delegates attacks, hits, and character setup; client Combat delegates feedback, animations, and input. Native actions handle desktop bindings and Sprint; successful GUI clicks and pointer tracking preserve Spin, Dash, and drag cancellation. All 112 source modules compile. Five existing pure specs, the new input spec/native-event harness, 55 server differential cases, and client presentation comparisons pass. StyLua and Rojo build pass; all 3,848 authored non-script instances retain their hierarchy/properties. New modules type-check cleanly using installed luau-lsp 1.68.1; existing dependency diagnostics remain, and pinned 1.69 could not load definitions. No Studio instance is connected, so live native routing, GUI hit testing, mouse projection, and device touch behavior remain unverified. Pre-existing workspace changes and authoring artifacts are preserved.

## Nested control cooldown
- [x] Archive obsolete Studio cooldown instances and verify a fresh live play session after Rojo sync.
- [x] Verify the updated Template.Container.Cooldown TextLabel through Studio MCP.
- [x] Bind cooldown text within Container and remove the obsolete image overlay logic.
- [x] Persist the authored template and copy its cooldown into all eight runtime and preview buttons.
- [x] Validate cooldown/status rendering and restart Rojo serve.

Review: MCP verified the new TextLabel and its gradient. Both UI exports use Container.Cooldown for all eight actions; other button properties are preserved. StyLua, Luau compilation, and the full Rojo build passed. Clone checks verified status rendering and weapon switching. After reconnection, Studio retained old unmanaged cooldowns alongside the new labels; WaitForChild selected an ImageLabel. Archived all 30 obsolete nodes in ServerStorage.CooldownBeforeNestedText and added a TextLabel assertion at binding. A fresh live session verified exactly one nested TextLabel per action, numeric Sprint/Dash countdowns, ring feedback, recovery, and no Text-member errors. The clean hierarchy persisted after stopping play. Rojo serves default.project.json on localhost:34872; Studio is in Edit mode.

## Agreed direction
- One persistent character; permanent RPG power applies in all PvP.
- Gear brackets measure effective equipment, enhancements, equipped skills, and permanent passives. Skill rating stays with the player when using a weaker build.
- 3v3 first; 5v5 after population and balance justify it. Dungeon farming is optional, with equivalent essential combat progression available through PvP.
- Chance based enhancement has guaranteed progress after failures and no item destruction. Downgrades remain undecided.
- Japanese weapon disciplines: two-handed Katana (dueling), Yumi (ranged pressure), Naginata (sweeping area control), Yari (precise thrusting).
- Open decisions: class flexibility, attainable power cap, trading, monetization, and bracket power tolerances.

## Slice 1: Yumi combat
- [x] Add shared weapon definitions and persist the selected starter discipline without changing profile version.
- [x] Allow Katana/Yumi selection in lobby or training; reject changes while queued, fighting, or in a dungeon.
- [x] Add an authored bow/arrow and server-timed hold/release shots with finite direction, sequence, stamina, cooldown, cover, team, and activity checks.
- [x] Add Piercing Shot, Volley, Quick Shot, and Pinning Shot through the existing four skill positions.
- [x] Adapt desktop/mobile input, visible skill names/costs, targeting range, previews, and bow presentation. Preserve Katana behavior.
- [x] Verify charge lifecycle, stale/duplicate requests, weapon switching, cover, friendly-fire authority rules, interruption, and existing combat in Studio.
- [x] Fix PC cursor aiming with a world raycast using raw mouse coordinates; render the preview at the hit surface's height after the camera update.

## Research-informed recommendations
- Keep progression unlocks constrained by equipped slots, inspired by Brawl Stars' [level-gated gadgets](https://support.supercell.com/brawl-stars/en/articles/gadgets-4.html) and [gear slots](https://support.supercell.com/brawl-stars/en/articles/gears-8.html). Do not grant every learned passive at once.
- Separate effective power eligibility from player skill and party matching. Wild Rift's [ranked changes](https://wildrift.leagueoflegends.com/en-us/news/game-updates/patch-7-2-ranked-changes/) reinforce treating ladder progression and matchmaking as distinct systems.
- Use explicit build trade-offs for weapon disciplines, inspired by Arena of Valor's [Enchantment system](https://www.arenaofvalor.com/webplat/info/news_version3/26190/33375/33376/33730/m19427/201907/819405.shtml). Its [3v3 mode](https://www.arenaofvalor.com/webplat/info/news_version3/26190/26191/27231/27232/m16887/201701/544806.shtml) supports testing smaller team objectives before expanding mode count.

These are design recommendations for this game's persistent-power rules, not copies of the reference games' economies.

## Following slices
1. Persistent character XP/levels, constrained loadouts, weapon mastery, inventory, and level locked skill ownership.
2. Locked 3v3 rosters, effective power brackets plus skill rating, party handling, and beginner protection.
3. Completion rewards with durable duplicate protection; recipes, salvage, weapon/skill enhancement, and persisted guarantee counters.
4. Resolve exclusive activity ownership; connect one dungeon and boss to the same material economy.
5. Naginata and Yari as distinct movesets; broaden build options after ranged/melee balance is verified.
6. Match history, reconnect reservations, AFK/reporting, onboarding, social goals, economy telemetry, and competitive seasons.
7. Additional objectives and 5v5 after queue population and performance checks.

## Review
Source inspection confirms Capture and Dungeon are enabled; this is not runtime proof. Capture currently has five slots per side and count-based local joining. Dungeon currently grants no loot. Only combat is confirmed working by the user. Pre-existing workspace changes must be preserved.

Slice 1 verification: shared charge/weapon and Capture authority specs passed; modified Luau modules compile, StyLua passes, and Rojo builds. Live Blink tests verified 28-damage full charge, stale cancel/duplicate release protection, all four skills, two-target piercing, pinning slow, cover, ForceField protection, rooted draw cancellation, queue selection rejection, weapon replacement, respawn restoration, and Katana damage.

PC aiming regression: the previous test repeated an incorrect GUI-inset subtraction and did not cover different ground heights. The replacement casts against actual surfaces and checks floor/raised surfaces and missing ground. Live raw-cursor measurements across moving camera frames stayed below one pixel; the released arrow matched the baseplate hit direction. The preview now renders after the camera and uses the cursor hit height.

Remaining validation: physical mobile controls, multiplayer latency/friendly-fire scenarios, and load/balance tests. Studio API access is disabled, so cross-session DataStore persistence is unverified. This slice adds weapon combat; progression, enhancement, bracket matchmaking, dungeon rewards, Naginata, and Yari remain in the following slices.

## Skill background assets: subtle washi
- [x] Generate Amber, Black, Blue, Gold, Green, Grey, Purple, and Red from the approved subtle Teal sample.
- [x] Check matching 1254px canvases and transparent outer padding; preserve the approved Teal file.
- [x] Publish as SkillBackgroundWashi<Color> (Teal: Skill Background Washi Teal) and verify names, creator, and image loading.
- [x] Add Shared.Combat.SkillAssets with the new backgrounds, existing vintage backgrounds, and gold frame.
- [x] Verify formatting, module loading, and Rojo mapping; save an export bundle.

Washi review: all nine new asset names and creator IDs verified through MarketplaceService; images loaded as 1024px EditableImages. Local 1254px PNGs retain transparent padding; Teal matches the approved sample byte-for-byte. Shared.Combat.SkillAssets loads in Studio, contains nine Washi and nine Vintage backgrounds plus the Gold frame, and passes StyLua. Rojo sourcemap confirms ReplicatedStorage.Shared.Combat.SkillAssets. Export: BrawlStarsSkillWashiAssets.zip. Roblox filtered the joined Teal name; its final display name is Skill Background Washi Teal.

## Charge brush artwork layers
- [x] Export the approved katana, dash, target, wind scrolls, and foreground frame without a color background.
- [x] Verify matching canvases, transparency, and unchanged artwork.
- [x] Package PNGs with their stacking order.

Review: all five PNGs are unchanged from the approved separated artwork, with 1254px square RGBA canvases and transparent unused areas. ZIP contents and integrity verified. Export: outputs/ChargeBrushLayers.zip. Place the existing color background below the supplied layers.

- [x] Extract the black brush texture into its own transparent overlay, separate from gold decoration and color background.

Black texture review: built-in image_gen output is 1254px RGBA, with transparent center and outer padding; visible pixels are neutral grayscale. Export: outputs/SkillBrushTextureBlack.png.

## Upload remaining skill artwork
- [x] Audit saved images against upload manifests and Studio assets; deduplicate identical files.
- [x] Upload only the 15 remaining images through Studio MCP.
- [x] Verify ownership and loading; save the asset-ID manifest and named Studio library.

Upload review: 15 new assets load as 1024px images with transparent corners and creator ID 10500660062. Reused 21 existing unique images, including two earlier horizontal layers identified in Studio. ServerStorage.GeneratedSkillArtwork contains the 15 descriptively named Decals. The MCP uploader assigns generic cloud titles; the manifest records those titles alongside filenames and IDs. Exports: outputs/RobloxSkillArtworkAssets.json and .csv. A repeated file audit finds no pending images.

## Assemble Charge sample in Studio
- [x] Inspect StarterGui.Controls.Charge and its Container/Icon layout.
- [x] Replace background, brush decoration, foreground, and Icon artwork with aligned image layers.
- [x] Verify image loading, ordering, alignment, and visible result; export the setup.

Assembly review: StarterGui.Controls.Charge now stacks Washi Teal, black brush decoration, Icon.WindScrolls/Dash/Katana/Target, and the vintage gold frame. All seven image assets loaded and share full-canvas bounds. Cooldown remains hidden at rest, above Icon and below the frame; Aim is hidden at rest. Title/hint are CHARGE/3. The overlapping Controls.T sample is hidden, and Charge is above it. Verified in Edit mode with a screenshot; gameplay behavior was not playtested. Exports: outputs/ChargeSampleSetup.json, AssembleChargeSample.luau, and ChargeSkillStudio.png.

## Matching Katana skill artwork
- [x] Confirm remaining Katana skill slots: Rising Crash, Wind Spin, Ground Shock.
- [x] Generate antique-gold weapon and separate motion/impact layers for each skill.
- [x] Check transparency, canvas registration, and assembled previews; package PNGs.

Artwork review: Rising Crash, Wind Spin, and Ground Shock each have separate Katana and Effects PNGs on matching 1254px RGBA canvases. Transparent corners verified; original generated alpha preserved. Browser previews checked at large, 96px, and 64px sizes. Ground Shock's impact was tightened to fit inside the shared frame. Existing backgrounds, black brush, and gold frame are reused in Common. Export: outputs/KatanaSkillLayers.zip, with layer manifest, built-in image_gen prompts, and self-contained preview. These six new skill layers are not yet uploaded to Roblox.

## Japanese Katana ornament layers
- [x] Generate skill-specific Japanese cloud, wind, and wave ornament overlays for Rising Crash, Wind Spin, and Ground Shock.
- [x] Verify they follow each skill's motion and preserve the weapon silhouette at button size.
- [x] Package the expanded layers with updated stacking settings and preview.

Pattern review: three new transparent 1254px Japanese ornament overlays use antique gold edges and textured charcoal bodies. Rising Crash follows its ascending slash with cloud ribbons; Wind Spin follows clockwise rotation with wind curls; Ground Shock uses upper clouds and lower wave bands. Browser comparisons verified at large, 96px, and 64px sizes. Patterns use centered 80% ImageLabels behind Effects and Katana; Layers.json specifies this placement. All six weapon/effect PNGs are unchanged. Export: outputs/KatanaSkillPatterns.zip, with shared assets, prompts, verification, and self-contained layer preview. No new Roblox uploads or Studio edits.

## Rebuild template-based input UI
- [x] Upload only missing Katana layer assets and clone StarterGui.Controls.Template into eight controls.
- [x] Rebuild the editor preview and playable CombatControls.Controls; preserve input bindings and support the nested artwork layout.
- [x] Persist Studio UI in the Rojo asset and verify image loading, cooldown/aim feedback, weapon switching, and visible layout.

Agreed scope: rebuild both playable controls and editor preview. Reuse existing Slash, Guard, Dash, and Run artwork; use separate Japanese layers for all four Katana skill slots.

Input UI review: all eight template-based buttons exist in StarterGui.Controls.Controls and StarterGui.CombatControls.Controls. Template is retained and hidden; old controls are backed up in ServerStorage.InputUiBeforeTemplate. Uploaded nine missing Katana layers, reused existing Charge/common/composed artwork, and recorded IDs/hashes in the asset manifests. New buttons retain Aim, Cooldown text, 32 cooldown segments, Title, Hint, and Cost. The controller supports Container.Icon artwork and its overlay; startup disables existing or later-added editor previews so they cannot overlap live controls. Rojo exports include InputPreview.project.json and the rebuilt CombatControls.Controls. StyLua and full Rojo build passed. Live checks verified startup/binding, eight loaded artworks, Dash button activation, Yumi labels/artwork hiding and Katana restoration, Charge LOCK feedback, and a temporary server cooldown fixture driving dimming/overlay/32 segments followed by recovery. The fixture was cleared and Studio returned to Edit mode. MCP virtual input rejects the One key as a reserved CoreGui input; number-key and physical touch/drag behavior remain manual checks. Existing animation access and DataStore warnings remain outside this UI change. Screenshot: outputs/InputUiStudio.png.
