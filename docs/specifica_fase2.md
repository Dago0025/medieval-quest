# Specifica della fase 2: nucleo di turno

Obiettivo: una partita che scorre un anno alla volta dal 1000 al 1700 senza combattimenti, con economia, costruzioni, reclutamento, movimento e salvataggi. Le regole vengono dal catalogo (`docs/catalogo_meccaniche.md`); dove manca la formula la regola è marcata `PROVVISORIA` nel codice, con il riferimento alla riga del catalogo.

Vincoli: ADR-003 (simulazione in `src/sim`, GDScript puro, nessun nodo, deterministica), ADR-004 (parametri in `data/regole/*.cfg`, non nel codice), ADR-005 (catalogo).

## 1. Stato di gioco (`src/sim/`)

| Classe | Contenuto |
|---|---|
| `GameState` | anno, anno finale (1700), epoca corrente, seme e stato del generatore casuale (`RandomNumberGenerator`), fazioni, province di terra, eserciti e flotte, agenti (solo conservati, attivi dalla fase 5), registro degli eventi dell'anno. Riferimenti ai dati statici: `CampaignData`, tabella unità, tabella edifici, regole. |
| `FactionState` | id, tesoro (int), viva, controllata dal giocatore. |
| `ProvinceState` | id, proprietario, edifici costruiti (famiglia → livello), coda di costruzione (max 4), coda di reclutamento (max 5), livello di tassa 0–4 (predefinito 2 = normale), ultimo reddito con il dettaglio per voce. |
| `Army` | id, fazione, regione in cui si trova (terra o mare), flotta sì/no, pile di unità (`UnitStack`: tipo, uomini, valore), percorso ordinato (elenco di regioni). |
| `QueueItem` | cosa (famiglia+livello o unità), anni rimanenti, costo pagato. |

Partita nuova (`GameSetup.new_game(campaign, units, buildings, rules, seed)`):
- tesoro di ogni fazione = `SetTreasury` (primo valore; gli altri sono per le difficoltà superiori);
- edifici della provincia dai `MakeBuilding` (token come `Castle15` o `SHIPYARD1` → famiglia + livello, senza distinzione di maiuscole);
- eserciti: le `MakeUnit` militari di una regione formano un esercito del proprietario della regione (max 16 unità per esercito, poi un altro); le navi formano una flotta nella prima zona di mare confinante (PROVVISORIA: il gioco usa probabilmente l'orientamento del porto); emissari e principesse diventano agenti con anno di nascita.

## 2. Comandi del giocatore e dell'IA (`GameCommands`)

Ogni comando valida e restituisce un esito (`ok`, `errore` in italiano). Lo stesso percorso serve al giocatore, all'IA e ai test.

| Comando | Regola |
|---|---|
| `set_tax(provincia, livello)` | solo proprie province, livello 0–4 |
| `queue_building(provincia, famiglia)` | prossimo livello esistente; requisiti del livello soddisfatti (condizioni del file edifici; un requisito `FAMIGLIA+N` è soddisfatto da un livello ≥ N: PROVVISORIA); fazione ammessa; epoca; coda < 4; tesoro sufficiente. Costo pagato all'accodamento (il manuale dice all'avvio: PROVVISORIA, cambia solo il momento). |
| `cancel_queue_item(provincia, coda, indice)` | rimborso del costo, progressi persi (manuale p26) |
| `queue_unit(provincia, unità)` | unità ammessa per fazione, epoca, regione/cultura; requisiti in edifici soddisfatti; coda < 5; tesoro sufficiente |
| `order_move(esercito, percorso)` | ogni passo confina con il precedente; eserciti di terra solo su terra, flotte solo su mare |

Il tesoro non può scendere sotto zero per spese (manuale p20).

## 3. Fine anno (`TurnProcessor.end_year(state)`)

Ordine fisso, deterministico (fazioni nell'ordine di dichiarazione, province nell'ordine di dichiarazione):

1. **Movimento**: ogni esercito con percorso avanza di una regione. Nella fase 2 può entrare solo in regioni proprie o in mare; un passo verso una regione di un'altra fazione si ferma e registra un «conflitto in sospeso» (risolto nella fase 3).
2. **Reddito** per ogni provincia propria non contesa (manuale p21: zero se ci sono eserciti di altre fazioni):
   - agricoltura = base `SetAttributes` × 0,52 × moltiplicatore terreno (livello delle coltivazioni: 1,0 / 1,2 / 1,4 / 1,6 / 1,8) × moltiplicatore tassa (0,75 / 0,9 / 1,0 / 1,1 / 1,25);
   - miniere = rendita del livello nel file edifici, fissa, senza tassa (scala da verificare: PROVVISORIA);
   - commercio = PROVVISORIA: somma dei valori delle merci della provincia × moltiplicatore dell'edificio commerciale (1,0 / 1,2 / 1,4 / 1,6) × 0,52 × fattore di regola, solo con porto ed edificio commerciale; la catena di flotte arriva con la fase 3;
   - arrotondamento all'intero (PROVVISORIA).
3. **Mantenimento**: somma del costo di mantenimento delle unità di ogni esercito e flotta, sottratta prima di sommare il reddito (manuale p20). Se il tesoro diventa negativo, si registra un avviso (cosa succede nel gioco è da ricavare).
4. **Costruzioni**: per ogni provincia avanza di un anno solo il primo elemento della coda; a zero anni il livello viene impostato.
5. **Reclutamento**: come sopra; l'unità nuova entra nell'esercito di guarnigione della provincia se ha meno di 16 unità, altrimenti in un esercito nuovo (manuale p26, p30).
6. **Calendario**: anno + 1; l'epoca passa a HIGH e LATE agli anni di `period_starts`; a 1700 la partita è finita.

## 4. Regole (`data/regole/economia.cfg`)

Tutti i numeri della sezione 3 in un file `ConfigFile`: scala annua, moltiplicatori di tassa, terreno, commercio, fattore commercio, massimo pile per esercito, lunghezza delle code, anno finale. Il codice legge solo da qui.

## 5. Salvataggi (`SaveGame`)

JSON in `user://salvataggi/`, con versione del formato, anno, seme e stato del generatore, e tutto lo stato dinamico. I dati statici non si salvano: si ricaricano dall'installazione. Un salvataggio ricaricato deve produrre esattamente lo stesso anno successivo dell'originale (test).

## 6. Criteri d'uscita

- Test unitari di ogni comando e di ogni passo del fine anno su uno stato piccolo costruito nel test.
- Partita automatica di 50 anni sui dati reali senza errori, deterministica a parità di seme.
- Reddito del primo anno per fazione stampato in un rapporto (`tests/esito_economia.txt`) da confrontare a mano con il gioco originale (laboratorio, catalogo §Economia).
- Interfaccia: barra con anno, epoca e tesoro; pulsante «Fine anno»; nel pannello della provincia tassa, costruzioni e reclutamento con le code; eserciti sulla mappa, selezione e ordine di movimento verso le province confinanti.
