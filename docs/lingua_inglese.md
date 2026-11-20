# Versione inglese (ADR-066)

## Come funziona

- Le frasi del codice sono scritte in italiano e passano da `Lang.t("...")` (`src/core/lang.gd`). Con l'italiano tornano
  come sono; con l'inglese si cercano in `data/lingue/en.tsv` (italiano TAB inglese, `\n` `\t` `\\` per a capo, tabulazione
  e barra rovescia). Una frase senza traduzione resta in italiano.
- Il modello si traduce PRIMA di riempirlo: `Lang.t("Esercito %d: da %s a %s.") % [id, da, a]`. Segnaposto uguali per
  numero, tipo e ordine nelle due lingue.
- Costanti (`const NOMI := [...]`): non si possono chiamare funzioni, quindi si traducono al momento dell'uso
  (`Lang.t(pair[1])`) e le voci si scrivono a mano in `en.tsv`.
- Grammatica delle fazioni (`CampaignUiText`): `fsubj` «The English», `fart` «the English», `fprep("di", id)` «of the
  English», `fprep("da", id, "by")` quando «da» e' d'agente, `fverb(id, Lang.t("dichiara"), Lang.t("dichiarano"))` (l'accordo
  plurale segue gli articoli italiani: «The English declare», «The Holy Roman Empire declares»), `fnames` con «and».
- Nomi dei dati in inglese: `data/lingue/en/` con le stesse sezioni delle tabelle italiane (`Lang.data_path`): fazioni,
  edifici, vizi e virtu', unita' che l'originale non ha. Unita' ed eventi dagli originali inglesi in `<gioco>/_INGLESE`
  (copiati da `_MOD_BACKUP_ORIG/PRE_ITALIANO_2026-11-09`, perche' `Loc/Italian` ora e' tradotta); province, titoli e cariche
  dai dati della XL (gia' in inglese).
- La lingua si sceglie nel menu iniziale e si salva in `user://impostazioni.cfg` (`lingua`); il gioco la riapplica a ogni
  avvio (`Lang.apply_saved` nel menu). I test girano in italiano (nessuno chiama `apply_saved`).
- Testi gia' scritti nei salvataggi (campo «testo» degli eventi passati) restano nella lingua in cui sono nati.

## Controllo

`python tools/testi_lingua.py` elenca le frasi di `Lang.t` senza traduzione e i segnaposto diversi; `--sospetti` anche le
stringhe italiane non avvolte. Il test `test_lingua` fallisce se una frase di `Lang.t` non ha la traduzione.

## Glossario (inglese britannico, termini dell'originale inglese di MTW)

| Italiano | English |
| :--- | :--- |
| Fine anno | End Year |
| esercito / armata (gruppo di unità sulla mappa) | army |
| pila (una unità di un esercito) | unit |
| pedina | piece |
| provincia / regione | province / region |
| zona di mare | sea zone |
| castello, fortezza, cittadella | castle, fortress, citadel |
| guarnigione | garrison |
| assedio / assalto | siege / assault |
| barricarsi nel castello | withdraw into the castle |
| fiorini | florins |
| tesoro / reddito / saldo | treasury / income / balance |
| agricoltura / miniere / commercio | farming / mining / trade |
| mantenimento / tasse | upkeep / taxes |
| lealtà / rivolta / ribelli | loyalty / revolt / rebels |
| emissario, principessa, spia, assassino | emissary, princess, spy, assassin |
| vescovo, cardinale, prete, inquisitore | bishop, cardinal, priest, inquisitor |
| ammiraglio, generale, comandante, governatore | admiral, general, commander, governor |
| re, principe, erede, nobile | king, prince, heir, noble |
| comando, terrore, acume, pietà, valore | command, dread, acumen, piety, valour |
| vizi e virtù | vices and virtues |
| crociata, jihad, scomunica | crusade, jihad, excommunication |
| Papa, Papato, Stato Pontificio | Pope, Papacy, Papal States |
| zelo, Inquisizione | zeal, Inquisition |
| alleanza, tregua, matrimonio, neutrale | alliance, ceasefire, marriage, neutral |
| blocco navale, flotta, nave, porto | naval blockade, fleet, ship, port |
| arruolare / reclutare, coda | recruit, queue |
| costruire, edificio | build, building |
| mercenari, congedare, riaddestrare, ripristina | mercenaries, disband, retrain, replenish |
| epoca (Alto, Pieno, Basso Medioevo) | era (Early, High, Late) |
| Salva, Carica, Indietro, Chiudi, Annulla, Conferma, Dettagli | Save, Load, Back, Close, Cancel, Confirm, Details |
| Facile, Normale, Difficile, Molto difficile | Easy, Normal, Hard, Very hard |
| Gli Auror | The Auror |
