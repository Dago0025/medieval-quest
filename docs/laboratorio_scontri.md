# Laboratorio degli scontri

Prove da eseguire nel gioco originale (Medieval: Total War, installazione Gold con la mod Auror
in evoluzione) per tarare la formula della risoluzione automatica del remake. La formula e tutti
i numeri sono PROVVISORI (catalogo r.105: "il computer pesa numero di uomini e vantaggi relativi,
ignora la tattica"): vivono in `data/regole/scontri.cfg` e si cambiano senza toccare il codice.

## Come si usa

- Ogni prova va **ripetuta** il numero di volte indicato. L'esito e' casuale: conta la
  frequenza delle vittorie (per esempio 7 su 10) e la media delle perdite, non il singolo scontro.
- Si annotano sempre: vincitore, uomini all'inizio e alla fine di ogni parte, chi si ritira.
- Usare la **risoluzione automatica** della battaglia (il calcolo del computer), non giocarla.
  Se l'originale offre solo la battaglia giocata, si annota l'esito giocato e lo si segnala: non e'
  confrontabile con il calcolo del remake.
- Partita personalizzata o battaglia rapida: va bene quello che permette di fissare unita',
  numero di uomini, livello di valore 0, capo senza stelle. In campagna, usare una provincia di
  pianura e due fazioni senza capi con stelle (gli Auror hanno un comando fisso: evitarli).
- I valori "il remake prevede" sono calcolati in Python con la stessa formula del codice, con le
  statistiche delle unita' lette da `MTW_XL_EARLY_UNIT_PROD11.TXT` dell'installazione
  il 2026-11-08. Le statistiche dipendono dalla mod Auror: se il file cambia, vanno ricalcolate
  (fattore di pila = 1 + 0,05 x (carica + mischia + difesa) + 0,05 x armatura + 0,14 x valore
  + 0,02 x morale, mai sotto 0,1).
- Probabilita' di vittoria dell'attaccante = Fa^2 / (Fa^2 + Fd^2), con Fd gia' moltiplicata per il
  bonus del difensore (campo 1,15; castello 1,5 / 2 / 2,5 / 3 / 4 secondo il grado; mare 1).
- Perdite: il perdente perde tra il 30% e il 90%, di piu' se era molto piu' debole; il vincitore perde
  una frazione minore. Le cifre tra parentesi sono uomini persi.

Fattori di pila usati sotto (valore 0, morale 0 salvo dove indicato): Spearmen 1,25 (carica 5,
mischia 0, difesa -1, armatura 1); FeudalKnights 1,95 (8, 4, 3, armatura 4); Peasants 0,91 (morale -2);
Archers 0,95; ogni nave 1 + 0,15 x attacco navale (Galley 1,15; Wargalley 1,45).

## Prova 1 - Eserciti pari

- **Setup**: 100 Spearmen contro 100 Spearmen, stessa fazione-tipo, valore 0, nessun capo con
  stelle, pianura, attacca A (battaglia campale, nessun castello).
- **Da annotare**: quante volte vince l'attaccante; uomini rimasti a vincitore e perdente.
- **Ripetizioni**: 20 (10 con A attaccante, 10 invertendo i ruoli per isolare il vantaggio di chi difende).
- **Il remake prevede**: vince l'attaccante nel 43,1% dei casi (il difensore ha +15%).
  Se vince l'attaccante: difensore -58, attaccante -33. Se vince il difensore: attaccante -62, difensore -27.
- **Cosa tarare**: `bonus_difensore` (g) se l'originale non mostra alcun vantaggio al difensore
  (allora 0), o se lo mostra piu' forte.

## Prova 2 - Due contro uno

- **Setup**: 200 Spearmen (due unita' da 100) contro 100 Spearmen; poi il contrario.
- **Da annotare**: frequenza di vittoria del lato piu' forte; perdite medie del vincitore.
- **Ripetizioni**: 20 per ciascun verso.
- **Il remake prevede**: 200 attacca 100: vittoria dell'attaccante 75,2%; se vince, -68 al difensore e
  -39 all'attaccante. 100 attacca 200: vittoria dell'attaccante 15,9%; se vince -96 al difensore e -55
  all'attaccante (vittoria "di Pirro"); se perde, -72 all'attaccante, -31 al difensore.
- **Cosa tarare**: l'esponente 2 della probabilita' (oggi Fa^2 / (Fa^2 + Fd^2), nel codice
  `Combat.win_probability`), `perdita_min`, `perdita_max`, `fattore_vincitore`. Se il 2:1 vince quasi
  sempre (>95%) l'esponente e' troppo basso; se vince meno del 70% e' troppo alto.

## Prova 3 - Cavalleria contro fanteria

- **Setup**: 40 FeudalKnights contro 100 Spearmen (cavalleria all'attacco); poi 100 Spearmen
  all'attacco contro 40 FeudalKnights; poi 80 FeudalKnights contro 100 Spearmen.
- **Da annotare**: vincitore, perdite. Nell'originale le lance dovrebbero contrastare la cavalleria
  (le Spearmen hanno la specialita' SPEAR): il remake NON modella le classi, usa solo le statistiche.
- **Ripetizioni**: 20 per ciascuna delle tre configurazioni.
- **Il remake prevede**: 40 cavalieri attaccano 100 lance: vittoria 22,8% (se vincono, -51 lance e -19
  cavalieri). 100 lance attaccano 40 cavalieri: vittoria 66,0% (-26 cavalieri, -23 lance).
  80 cavalieri attaccano 100 lance: vittoria 54,1% (-61 lance, -23 cavalieri).
- **Cosa tarare**: i pesi `attacco` (a) e `armatura` (b). Se l'originale premia la cavalleria piu'
  del remake, alzare a e b; se premia le lance, serve un moltiplicatore per classe (non c'e': va
  aggiunto come nuova regola, e' la prima cosa da decidere guardando questi numeri).

## Prova 4 - Qualita' contro quantita'

- **Setup**: 200 Peasants (morale -2) contro 40 FeudalKnights (cavalieri in difesa).
- **Da annotare**: vittorie dei contadini su 20; perdite medie.
- **Ripetizioni**: 20.
- **Il remake prevede**: vincono i contadini all'attacco nell'80,5% dei casi (-28 cavalieri, -35 contadini);
  se perdono, -100 contadini e -20 cavalieri.
- **Cosa tarare**: se l'originale fa vincere i cavalieri nella maggior parte dei casi, i pesi di
  carica / difesa / armatura sono troppo bassi (la qualita' vale piu' del numero).

## Prova 5 - Assedio di un forte con fame

- **Setup**: provincia con castello di grado Fort (livello 1 della famiglia CASTLE), guarnigione
  di 100 Spearmen; l'assediante ha 100 Spearmen fuori, **senza dare mai l'assalto**.
  Ripetere con Keep (livello 4), Castle (7), Citadel (10), Fortress (13) se si riesce a costruirli.
- **Da annotare**: dopo quanti anni (turni) la guarnigione si arrende; se l'assediante perde uomini
  per fame o malattia; se la guarnigione esce a combattere da sola (sortita) e quando.
- **Ripetizioni**: 3 per grado (l'esito dovrebbe essere deterministico).
- **Il remake prevede**: resa per fame dopo 1 anno (Fort), 2 (Keep), 3 (Castle), 4 (Citadel), 5 (Fortress).
  Nessuna perdita dell'assediante. Sortita solo se la forza della guarnigione supera di oltre
  2 volte quella degli assedianti (per esempio 250 Spearmen dentro contro 100 fuori: 2,5 volte;
  sortita vinta dalla guarnigione nell'82,5% dei casi, -71 assedianti, -41 guarnigione).
- **Cosa tarare**: `anni_fame` per grado, `soglia_sortita`. Annotare anche se la guarnigione
  piccola (~5 uomini) non puo' essere affamata (nota del catalogo, non modellata).

## Prova 6 - Assalto al castello

- **Setup**: 200 Spearmen assediano 100 Spearmen dentro un castello, si ordina l'assalto. Ripetere
  per ogni grado di castello disponibile (Fort ... Fortress). Variante: 100 Spearmen contro 60 Archers
  in un Fort.
- **Da annotare**: esito dell'assalto, uomini persi, se la guarnigione sopravvive (nel remake,
  se l'attaccante vince la guarnigione e' annientata, regola PROVVISORIA).
- **Ripetizioni**: 20 per grado.
- **Il remake prevede** (200 attaccano 100): vittoria dell'attaccante Fort 64,0% (-48 attaccanti),
  Keep 50,0% (-60), Castle 39,0% (-71), Citadel 30,8% (-81), Fortress 20,0% (-100).
  100 Spearmen contro 60 Archers in un Fort: 68,1% (-22 attaccanti, guarnigione annientata).
  Se l'assalto fallisce: l'attaccante perde 111 (Fort) ... 140 (Fortress) su 200 e si ritira.
- **Cosa tarare**: `moltiplicatore_assalto` per grado e `assalto_annienta` (se nell'originale
  la guarnigione sopravvive in parte, metterlo a `false`).

## Prova 7 - Battaglia navale

- **Setup**: 3 Galley contro 2 Galley in mare; poi 2 Wargalley contro 3 Galley. Ciascuna nave e'
  un'unita' da 1.
- **Da annotare**: navi affondate per parte, vincitore.
- **Ripetizioni**: 30 (gli interi sono piccoli: serve molta statistica).
- **Il remake prevede**: 3 Galley attaccano 2: vittoria 69,2% (affondano 1 nave nemica, perdono 1).
  2 Wargalley attaccano 3 Galley: vittoria 41,4%.
  Le perdite si arrotondano al numero intero di navi (0-2).
- **Cosa tarare**: `navale` (e), `bonus_difensore_mare`. Annotare se le navi con piu' attacco
  navale (Wargalley 3, Cog 4) prevalgono davvero.

## Prova 8 - Valore e comando (facoltativa)

- **Setup**: 100 Spearmen di valore 3 contro 100 Spearmen di valore 0; poi un capo a 3 stelle contro
  uno senza stelle.
- **Da annotare**: frequenza di vittoria.
- **Il remake prevede**: ogni livello di valore pesa +14% di forza (c = 2a + 2d, catalogo r.74),
  ogni stella +5% (f = a, catalogo r.119). Con valore 3 il fattore di pila e' 1,67 contro 1,25.
  Per la probabilita' si ricalcola con la formula sopra.
- **Cosa tarare**: `valore` (c) e `peso_stella` (f).

## Dopo le prove

Per ogni prova: riportare le frequenze osservate, confrontarle con le previsioni, modificare
`data/regole/scontri.cfg` e rieseguire la simulazione.
