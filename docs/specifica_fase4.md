# Specifica della fase 4: province e personaggi

Obiettivo: regni e dinastie vivi. Re, eredi, principi e principesse nascono, crescono, invecchiano e muoiono; i generali comandano gli eserciti con i loro attributi; le province hanno una lealtà che può portare a rivolte; le fazioni distrutte possono riemergere; i generali sleali possono scatenare una guerra civile. Le regole vengono dal catalogo (§Personaggi e dinastie, §Vizi, virtù e titoli, §Province e lealtà); quelle senza formula sono `PROVVISORIA`, con i parametri in `data/regole/personaggi.cfg` e `data/regole/province.cfg`.

Vincoli: ADR-003, 004 (Auror integrata: `data/regole/auror.cfg`), 005, 008, 009. Determinismo con `state.rng`.

La fase si divide in due blocchi, implementati in sequenza perché toccano gli stessi file: **4a personaggi** e **4b province**.

## 4a. Personaggi e dinastie

### Modello (`src/sim/character.gd`, `Character`)

id, nome, numerale (solo re), fazione, ruolo (`capo`, `erede`, `principe`, `principessa`, `generale`), anno di nascita, sangue reale, attributi 0–10 (comando, terrore, pietà, acume, lealtà; influenza solo per il capo), vizi e virtù (id → livello), titolo provinciale, carica di Stato, esercito comandato, vivo. `GameState.characters` in ordine di id.

### Partita nuova

- Capo e eredi da `SetStartLeader` / `AddHeir` / `PlaceLeader` dello startpos (formato da ricavare dai file e dal LEGGIMI Auror; gli Auror hanno `SetStartLeader 0 1 1`).
- Nomi dalle liste di `HeroesData` (nomi di battesimo, nomi reali, principesse); re famosi: se nome e numerale di un nuovo re coincidono con un `FAMOUS_KINGS`, prende quegli attributi e vizi/virtù (manuale p16).
- Ogni esercito senza capo riceve un generale generato (nome dalla lista della fazione, attributi casuali bassi: PROVVISORIA).
- Eroi famosi (`FAMOUS_HEROES`): compaiono nell'anno indicato nella loro regione se è della loro fazione (o nella capitale), con i loro attributi; `ID_LIMBO` = capitale.
- Titoli e cariche iniziali da `AddTitle` / `AddOffice` dello startpos.

### Regole annuali (fine anno, dopo gli scontri e prima dell'economia)

| Regola | Dettaglio |
|---|---|
| Invecchiamento e morte | Logica già ricavata dall'eseguibile (scheda MTW del Second Brain): soglia = 40 + casuale 0–4, +10 per sangue reale ed eroi; oltre la soglia probabilità annua (età − soglia) / 50. Il re degli Auror non muore di vecchiaia (`re_immortale`). |
| Nascite | PROVVISORIA: un capo tra 18 e 55 anni ha probabilità `p_nascita` di un figlio; maschio o femmina al 50%. Il primo figlio maschio è l'erede. |
| Maggiore età | Figli maschi a 16 anni diventano principi (generali di sangue reale); figlie a 15 diventano principesse (agenti, ruolo pieno nella fase 5), si ritirano a `eta_ritiro_principessa` (32). |
| Successione | Erede adulto; altrimenti principe di sangue reale (rischio di guerra civile, 4b); altrimenti la fazione si estingue: le sue province diventano ribelli (manuale p18). Attributi dell'erede entro ±3 da quelli del re (PROVVISORIA, catalogo); nome reale unico «Darkos» per gli Auror con numerale crescente. |
| Influenza | Del capo: −1 ogni 2 province perse, +1 ogni 2 conquistate (catalogo, documentato); limiti 0–10; Auror fissa a 9. |
| Comando in battaglia | Le stelle del comandante dell'esercito entrano in `Combat` al posto del valore fisso; Auror: `comando_fisso` 9 per tutti i suoi personaggi. |
| Acume ed economia | Governatore +10% di agricoltura e commercio per punto; re +2% su tutto il reame (catalogo, Media). |
| Vizi e virtù | Elenco dei nomi ricavato dai testi Loc del gioco (dove compaiono); effetti e inneschi PROVVISORI per un primo gruppo documentato (catalogo: catene Leadership, Dread, Vacillator dopo ritirate ripetute, Killer Instinct, Butcher) in `data/regole/vizi_virtu.cfg`; gli altri restano senza effetto finché non si ricavano. |
| Generali | Dopo una battaglia vinta il comandante può guadagnare una stella (PROVVISORIA `p_stella_vittoria`), dopo una sconfitta perderla (`p_stella_sconfitta`). |

### Comandi

`assign_title(state, f, character_id, province)` e `revoke_title(...)` (titolo = governatore della provincia; revoca: −`calo_lealta_revoca`); `set_commander(state, f, army_id, character_id)` per un generale presente nella stessa regione.

### Eventi

`EV_BIRTH`, `EV_COMING_OF_AGE`, `EV_DEATH`, `EV_SUCCESSION`, `EV_FACTION_EXTINCT`, `EV_HERO_APPEARS`, `EV_VNV_GAINED`, `EV_TITLE_CHANGED`, `EV_STAR_CHANGED`.

## 4b. Province: lealtà, rivolte, guerra civile

| Regola | Dettaglio |
|---|---|
| Lealtà obiettivo | Somma (catalogo, Media): base `lealta_base` (PROVVISORIA) + termine tassa (+25/+10/0/−10/−25) + guarnigione (+16 ogni 100 uomini) + edifici (tabella del catalogo) − ribellione regionale (`SetRegionRebels`, in unità da 10%) − religione diversa dalla fazione (PROVVISORIA) − distanza dal capo (PROVVISORIA per passo) + terrore del governatore (PROVVISORIA). |
| Lealtà corrente | Si avvicina all'obiettivo di una frazione `deriva` all'anno (catalogo: «adattamento lento»). |
| Rivolta | Sotto 100: probabilità annua proporzionale a (100 − lealtà) (`k_rivolta`); nasce un esercito ribelle proporzionato alla rendita della provincia, che assedia il castello o conquista la provincia se è sguarnita. Tipi di ribelli del manuale p24 come etichetta. |
| Propagazione | Le rivolte possono estendersi alle province confinanti (PROVVISORIA `p_propagazione`). |
| Riemersione | Una fazione estinta che possedeva la provincia può riemergere in una provincia sotto 120 con un esercito e un nuovo capo (catalogo: solo fazioni non del giocatore). |
| Guerra civile | Se molti generali hanno lealtà ≤ 3 (`quota_sleali`) o un generale forte e sleale (comando ≥ `comando_promotore`) sta in una provincia diversa da quella del capo: probabilità annua; i generali sleali, i loro eserciti e le province che governano passano ai ribelli lealisti (PROVVISORIA: la divisione completa con scelta del lato arriva più avanti). |
| Lealtà dei generali | Scende con tasse alte, sconfitte, revoca dei titoli; sale con titoli, matrimoni (fase 5), influenza del capo (PROVVISORIA). Auror: `fedelta_fissa` 9. |

Eventi: `EV_LOYALTY_LOW`, `EV_REBELLION`, `EV_REBELLION_SPREAD`, `EV_FACTION_REEMERGED`, `EV_CIVIL_WAR`.

## Salvataggi

Versione 3: personaggi, lealtà delle province, contatori; carica le versioni 1 e 2 creando i personaggi come in una partita nuova.

## Interfaccia (dopo 4a e 4b)

- Pannello della fazione (tasto o pulsante «Corte»): capo, eredi, principi, principesse, generali con attributi, vizi e virtù, età, titoli.
- Pannello dell'esercito: comandante con stelle e attributi; cambio del comandante.
- Pannello della provincia: lealtà corrente e obiettivo con il dettaglio dei termini, governatore, assegnazione e revoca del titolo.
- Resoconto di fine anno con nascite, morti, successioni, rivolte, guerre civili, eroi.

## Criteri d'uscita

- Test unitari di ogni regola.
- Simulazione di 200 anni sui dati reali con successioni, rivolte e almeno una guerra civile o estinzione, deterministica, senza errori e con stato coerente (ogni esercito ha un comandante vivo della sua fazione, ogni fazione viva ha un capo).
