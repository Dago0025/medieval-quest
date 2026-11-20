# Specifica della fase 3: scontri

Obiettivo: eserciti e flotte possono attaccare; battaglie, assedi e scontri navali si risolvono in automatico a fine anno; le province cambiano proprietario. È il primo traguardo giocabile. Le formule della risoluzione automatica non sono documentate (catalogo §Assedi e risoluzione automatica): sono tutte `PROVVISORIA`, con i parametri in `data/regole/scontri.cfg`, da tarare con prove nel gioco originale.

Vincoli: ADR-003, 004, 005, 008. Determinismo: ogni estrazione casuale usa `state.rng`, in un ordine fisso.

## 1. Guerra e diplomazia minima

- `GameState.wars`: insieme di coppie di fazioni in guerra (chiave `"A|B"` con A < B). I ribelli (`FN_REBEL`) sono in guerra con tutti.
- Ordinare un movimento verso una regione di un'altra fazione, o dove ci sono suoi eserciti, è un attacco: la guerra viene dichiarata a fine anno, quando il movimento parte (evento `EV_WAR_DECLARED`). La diplomazia vera arriva nella fase 5.

## 2. Comandi nuovi o cambiati (`GameCommands`)

| Comando | Regola |
|---|---|
| `order_move` | ora ammette regioni ostili (attacco). Un esercito che assedia non può muoversi senza togliere l'assedio (il movimento lo toglie). |
| `order_assault(state, f, army_id)` / `cancel_assault` | solo per un esercito che assedia: a fine anno assalta il castello invece di attendere. |
| `can_order_assault(state, f, army_id)` | solo controllo, per l'interfaccia. |

## 3. Fine anno (ordine aggiornato)

1. **Movimento** (come fase 2, ma gli attacchi entrano nella regione bersaglio). Le dichiarazioni di guerra nascono qui.
2. **Battaglie in campo**: per ogni regione, nell'ordine di dichiarazione, se ci sono eserciti di fazioni in guerra fuori dal castello, si combatte. Attaccante = chi è entrato quest'anno; difensore = gli altri. Più fazioni: si risolvono a coppie nell'ordine di dichiarazione delle fazioni. Le flotte combattono solo con flotte, nelle zone di mare.
3. **Ritirate** del perdente (manuale p32, cinque casi, in quest'ordine):
   1. difensore nella propria provincia con castello e posto in guarnigione (max 16 unità, la cavalleria conta 2): entra nel castello → inizia l'assedio;
   2. una provincia confinante propria: ci si ritira (la prima nell'ordine di `SetNeighbours`);
   3. attaccante: torna alla regione da cui è partito;
   4. arrivato dal mare (sbarco): catturato;
   5. nessuna via: catturato.
   Catturato = eliminato in questa fase (il riscatto arriva con agenti e diplomazia).
4. **Assedi**: `GameState.sieges` (regione → `SiegeState`: fazione assediante, anni di assedio, eserciti assedianti). Ogni anno:
   - se l'assediante ha ordinato l'assalto: battaglia d'assalto con il moltiplicatore difensivo del castello;
   - altrimenti +1 anno; la guarnigione cede per fame dopo `anni_fame[livello castello]` anni (parametro);
   - sortita: la guarnigione esce se la sua forza supera `soglia_sortita` × quella dell'assediante; una sortita persa annienta la guarnigione (manuale p31);
   - se gli assedianti se ne vanno o muoiono, l'assedio finisce.
5. **Conquista**: una provincia passa all'attaccante quando non ci sono più eserciti ostili né guarnigione. Code svuotate, tassa normale, edifici mantenuti (PROVVISORIA: il gioco ne distrugge alcuni). Se il castello è vuoto, la conquista è immediata dopo la battaglia in campo.
6. **Fazioni distrutte**: senza province e senza eserciti → `alive = false` (`EV_FACTION_DESTROYED`).
7. Poi reddito, mantenimento, costruzioni, reclutamento, calendario come nella fase 2. Le province assediate o contese non producono reddito (manuale p21).

## 4. Risoluzione automatica (`src/sim/combat.gd`, `Combat`)

Tutto `PROVVISORIA`; parametri in `data/regole/scontri.cfg`.

- Forza di una pila = uomini × (1 + a·(carica + mischia + difesa) + b·armatura + c·valore + d·morale). Navi: uomini × (1 + e·attacco navale).
- Forza di un esercito = somma delle pile × (1 + f·stelle di comando del capo). Il capo e le stelle arrivano con la fase 4: fino ad allora stelle = 0, tranne gli Auror, che hanno `comando_fisso` in `data/regole/auror.cfg` (9).
- Bonus del difensore in campo (g), moltiplicatore del castello per livello negli assalti (tabella).
- Vincitore: l'attaccante vince con probabilità Fa² / (Fa² + Fd²), estratta con `state.rng`.
- Perdite: il perdente perde una frazione tra `perdita_min` e `perdita_max` crescente con il rapporto di forze; il vincitore perde la frazione del perdente × (Fp / Fv) × `fattore_vincitore`. Le perdite si distribuiscono sulle pile in proporzione agli uomini; una pila sotto 1 uomo sparisce.
- Il vincitore guadagna valore: +1 su ogni pila sopravvissuta con probabilità `p_valore` (max 9).

Risultato (`BattleResult`): attaccanti, difensori, forze, vincitore, perdite per fazione, ritirate e catture, tipo (`campo`, `assalto`, `sortita`, `navale`). Ogni battaglia produce un evento `EV_BATTLE` con i dettagli.

## 5. Eventi nuovi (`GameState`)

`EV_WAR_DECLARED`, `EV_BATTLE`, `EV_RETREAT`, `EV_CAPTURED_UNITS`, `EV_SIEGE_STARTED`, `EV_SIEGE_ENDED`, `EV_ASSAULT`, `EV_SALLY`, `EV_STARVED`, `EV_PROVINCE_CAPTURED`, `EV_FACTION_DESTROYED`. Ogni evento è un Dictionary con almeno `tipo`, `anno`, `fazione`, `regione`, `testo` (in italiano, leggibile), più i dettagli. `EV_PENDING_CONFLICT` non si produce più.

## 6. Salvataggi

Versione 2 del formato: aggiunge guerre, assedi, ordini d'assalto, eserciti nel castello. I salvataggi della versione 1 si caricano con guerre e assedi vuoti.

## 7. Interfaccia

- Clic destro su una regione ostile confinante: ordine d'attacco (freccia rossa).
- Province assediate: simbolo sulla mappa e riga nel pannello (anni di assedio, anni alla resa per fame).
- Esercito che assedia: pulsante «Assalta il castello» (o annulla) nel pannello dell'esercito.
- Finestra di fine anno: le battaglie con forze, vincitore e perdite; conquiste, assedi, distruzioni di fazioni.
- Barra o riepilogo: fazioni con cui si è in guerra.

## 8. Criteri d'uscita

- Test unitari di forza, esito, perdite, ognuno dei cinque casi di ritirata, assedio con fame, assalto, sortita, conquista, distruzione di una fazione, determinismo, salvataggio v2 e caricamento v1.
- Partita automatica di 100 anni sui dati reali in cui ogni fazione attacca a caso un vicino ogni 5 anni: nessun errore, province e fazioni coerenti (ogni provincia ha un proprietario vivo o i ribelli).
- Scenari di prova da giocare nel gioco originale per tarare la formula (elencati in `docs/laboratorio_scontri.md`).

## 9. Trasporto via mare (aggiunta del 2026-11-08)

Segnalato da Federico: le flotte esistono ma gli eserciti non si imbarcano. Regola del manuale (p33–34, catalogo §Movimento e flotte, riga «Catene e sbarchi»):

- Un esercito di terra in una provincia costiera **con porto** (`SetPort` e edificio PORT costruito: PROVVISORIA, i Vichinghi non ne avevano bisogno ma qui non ci sono) può raggiungere in un solo anno qualunque provincia costiera collegata da una **catena di zone di mare contigue, ognuna con almeno una flotta propria** (alleati dalla fase 5). La prima zona confina con la provincia di partenza, l'ultima con quella d'arrivo.
- Una sola flotta ostile in una zona della catena la interrompe (anche se è del proprietario della provincia d'arrivo).
- Nessun limite di capienza delle flotte. Le flotte non si spostano per il trasporto.
- Si calcola la catena più corta (ricerca in ampiezza sulle zone di mare, ordine di `SetNeighbours` per il determinismo).
- Lo sbarco in una provincia ostile è un attacco; chi perde dopo uno sbarco è catturato (ritirata caso 4, già presente: `from_region` = ultima zona di mare della catena).
- La catena si ricontrolla a fine anno, al momento del movimento: se nel frattempo è interrotta, l'esercito resta dov'è e si registra `EV_TRANSPORT_BLOCKED`.

API: `GameCommands.sea_route(state, f, da, a) -> PackedStringArray` (vuoto se non raggiungibile), `GameCommands.sea_destinations(state, f, army_id) -> PackedStringArray`, e `order_move` accetta come percorso una sola provincia non confinante se raggiungibile via mare (salva la catena in `Army.sea_route`; il risultato contiene `"via_mare": true` e `"catena"`). Salvataggi: `sea_route` incluso (versione 2, campo facoltativo).

Interfaccia: con un esercito selezionato, le province raggiungibili via mare si evidenziano leggermente; clic destro su una di esse ordina il trasporto, con freccia tratteggiata lungo la catena (rossa se è uno sbarco ostile).
