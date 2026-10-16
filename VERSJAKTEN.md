# Versjakten – överlämning

Svenskt dagligt bibelversspel (inspirerat av Versle). Byggt av Henrik Harknäs med Claude.
Mål: öka ungas intresse för hela Bibeln. Ev. intäkter ska gå till mission (Pingstkyrkan Katrineholm).

## Länkar
- Spelet: https://kinghenrik98.github.io/Versjakten/
- Betan: https://kinghenrik98.github.io/Versjakten/beta/
- Admin: https://kinghenrik98.github.io/Versjakten/admin/ (känner igen admin-profilen på telefonen, annars personlig kod)
- Repo: github.com/Kinghenrik98/Versjakten (GitHub Pages från `main`)
- Databas: Supabase-projekt `qccrlaxzfiddgfsxozim` (SQL körs i Supabase → SQL Editor)

## Filer i repot
- `index.html` – vanliga versionen (byggd)
- `beta/index.html` – betan (byggd)
- `admin/index.html` – adminsidan (byggd)
- `src/` – källkod:
  - `beta_template.html` – EN mall för både vanlig och beta. Flaggan `IS_BETA` styr skillnader.
  - `admin_template.html` – adminsidan
  - `build_beta.py` – bygger `beta_index.html`, `main_index.html` och `admin_index.html`
  - `data.json` – 66 böcker, verser per kapitel, 426 verser (Svenska Folkbibeln 2015, SFB15)
  - `*.sql` – alla databasändringar i den ordning de kördes (se nedan)
  - `template.html` / `build.py` – den allra första versionen (används inte längre)

### Bygga och publicera
```
cd src
python3 build_beta.py https://qccrlaxzfiddgfsxozim.supabase.co <publishable-nyckel>
cp main_index.html ../index.html        # bara när något ska ut i vanliga
cp beta_index.html ../beta/index.html
cp admin_index.html ../admin/index.html
git commit -am "..." && git push
```
Publishable-nyckeln finns i de byggda html-filerna (den är publik, inte hemlig).
Pages tar ~1 minut att uppdatera. Testa nya idéer i betan först.

## Spelet
- 3 dagliga verser, samma för alla. START_DAY = 2026-10-14, tidszon Stockholm.
  Vers-index = (dagnr·3 + runda) mod antal verser.
- Gissa bok + kapitel:vers (4 siffror), 5 försök. Färger som Wordle, pil tidigare/senare.
- Poäng: 50/35/25/15/10 på försök 1–5. Ej klarat: 8 (rätt bok+kapitel), 5 (rätt bok), annars 0.
- "Ge kontext"-knapp efter varje vers (ingen automatisk popup). Länk till kapitlet i YouVersion (SFB15, id 1223).
- Färgförklaring visas en gång efter första gissningen.

## Funktioner
- Profiler (namn, figur, ort, församling) med personlig kod som fungerar som lösenord.
- Startsida: streak 🔥, veckoremsa, stor spelknapp, Maraton, gruppens rad.
- Meny: Spela, Topplista, (Utbildning – bara beta), Grupper, Jag.
- Topplistor: Hela Sverige, Min församling, Min ort, Församlingsligan, grupper; Idag/Veckan/Totalt/Maraton.
- Jämför gissningar med andra.
- Maraton (Valters idé): slumpade verser i rad tills miss; rekord + topplista.
- Märken, bibelresa (66 böcker), statistik.
- Församlingsregister: välj i lista, föreslå ny → admin godkänner.
- Grupper: inbjudningslänk `?grupp=KOD`. Gruppsida med:
  - 5 verser/dag = dagens 3 + 2 extra för gruppen, en gemensam topplista
  - Chatt (bara medlemmar), reaktioner, böneämnen, spoilerskydd, automatiska resultatinlägg
  - 👑 dagens krona (bäst idag, annars gårdagens vinnare), 🔥 gruppens eld
- Bjud in fler (dela-knapp), versionsbyte Vanlig/Beta/Admin för admin och testare.
- Utbildning (bara beta): ramsa för Paulus brev, "sätt i ordning"-spel, alla 66 böcker med BibleProject-film, tips (TELOS, Kärnbibeln-appen, BibleProject).
- Exempelreklam "Godispengen" finns bara i betan.

## Databas (Supabase)
Tabeller: `profiles` (koder dolda via kolumnrättigheter; `is_admin`, `is_tester`), `groups`, `group_members`,
`beta_scores` (dagens verser), `marathon_runs`, `churches`, `group_scores` (gruppens extra verser, runda 4–5),
`group_messages`, `message_reactions`. Gamla tabellen `scores` hör till första versionen.
All skrivning sker via RPC-funktioner (security definer) som kontrollerar personlig kod:
`save_profile`, `login_profile`, `submit_score`, `submit_marathon`, `create_group`, `join_group`, `leave_group`,
`my_groups`, `submit_group_score`, `get_messages`, `send_message`, `react_message`, `delete_message`,
`my_group_activity`, `admin_*`.
SQL-filer i körordning: `beta_schema.sql`, `beta_maraton.sql`, `beta_kyrkor.sql`, `admin.sql`, `beta_grupp.sql`
(+ två små: grant select (is_admin) och is_tester-kolumnen för Valter och Johan).

## Personer
- Henrik (admin), Valter och Johan Öhrvall (betatestare).

## Önskemål om arbetssätt
- Svenska, korta och raka svar. Rätta mig när jag har fel. Gissa inte om knappar/menyer.
- Bolla idéer och visa skisser/skärmbilder innan större ändringar.
- Nya saker i betan först. Rör inte vanliga versionen utan att jag säger till.

## Idéer som inte är gjorda än
- Stänga luckan så att gruppnamn/medlemmar/gruppoäng bara syns för medlemmar.
- Moderering av chatten (ordfilter / anmäl-knapp till admin).
- Fler verser, "lägg till på hemskärmen", Swish-gåva, gratis/reklamfritt under 18.
