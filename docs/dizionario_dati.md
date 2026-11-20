# Dizionario dati - campagna di Medieval: Total War (Gold/VI 2.01) + MTW XL 3.0 (+ mod "Auror")

Scopo: base per riscrivere il SOLO livello campagna (1000-1700) in un motore nuovo.
Convenzioni: "riga N" = riga fisica del file (le righe sono identiche con o senza CR). "(dedotto)" = significato non scritto nei file, ricavato da nomi, valori, script Auror o dai README. Nessun file in uploads e' stato modificato; gli script e i CSV derivati sono in `/home/claude/mtw_plan/tools/` e `/home/claude/mtw_plan/out/`.
Cartella sorgente: `/mnt/user-data/uploads/Total War Medieval 1 Gold/` (abbreviata `G/`). Codifica cp1252, CRLF.

## 0. Sintesi e numeri chiave

| Voce | Valore | Dove |
|---|---|---|
| Fazioni dichiarate (compresa FN_REBEL = 0) | 31 (30 reali). Limite scritto: 32 | EARLY_XL.TXT righe 84-114 |
| Fazioni attive (SetActiveFaction) | 27 (di cui tutte FT_MAJOR = giocabili). Spente: Golden Horde (nessuna riga), Norvegesi e Svedesi (commentate da Auror) | righe 2019-2048 |
| Regioni di terra | 107 (limite scritto 254). Assegnate a una fazione: 85; ribelli: 22 | righe 140-246, 2316-2431 |
| Regioni di mare | 36 (ID successivi a quelli di terra) | righe 260-295 |
| Merci commerciabili | 24 | righe 623-646 |
| Risorse minerarie | 5 (IRON, COPPER, SILVER, GOLD, SALT): 33 regioni ne hanno | righe 1907-2009 |
| Unita'/righe nel file prod (EARLY = LATE come nomi e ordine) | 256 righe = 236 militari (127 fanteria, 83 cavalleria, 13 artiglieria, 13 navi) + 5 MOUNT (cavalcature, non unita') + 15 agenti/eventi strategici | MTW_XL_EARLY_UNIT_PROD11.TXT dalla riga 21 |
| Tipi di agente/azione strategica (colonna "Unit type") | 15 (SPY, ASSASSIN, EMISSARY, PRINCESS, BISHOP, CARDINAL, INQUISITOR, GRAND_INQUISITOR, PRIEST (+Shaman), ORTHODOX_BISHOP, MULLAH, ULAMA, CRUSADE, JIHAD); in `TYPE` dei personaggi famosi ne compaiono 13 | unit prod, heroes riga 13-15 |
| Edifici (famiglie) / livelli totali | 46 famiglie / 112 livelli (CASTLE da solo 15). 64 token distinti usati nello startpos | MTW_XL_EARLY_BUILD_PROD13.TXT |
| Periodi | 3: EARLY, HIGH, LATE. Soglie startpos: 1000 / 1205 / 1321 | EARLY_XL.TXT righe 30-34 |
| Adiacenze | SetNeighbours esplicito: 388 coppie (208 terra-terra, 112 terra-mare, 68 mare-mare). Dalla bitmap LukMap: 387/388 recuperate, 7 in piu' | sezione 8 |
| Mappa lookup | LukMap.Lbm = LUKUPMAP.LBM (byte identici), 2048x1536, 251 indici usati | sezione 8 |
| Eventi storici (solo testi, niente trigger) | 71 titoli+testi in Events.txt righe 5078-5260; obiettivi di gloria: 51 obiettivi con descrizione (circa 45 con date di calcolo nel solo testo (glorygoals.txt) | sezione 5/7/11 |

Le 5 scoperte principali:
1. `SetNeighbours` (righe 690-833) e' la fonte autorevole delle adiacenze: ma la bitmap LukMap le riproduce quasi al 100% (indice palette = 2*(ordine_dichiarazione+1) per la terra, +1 = variante "ombreggiata"; mare = 216+k). Con le coordinate `SetCastle/SetOrigin/SetBorderInfo` dividendo per 16 si cade sui pixel della bitmap.
2. Le regole di costruzione e produzione sono tutte dati (condizioni a livelli con `{A,B}` = AND e gruppi annidati = OR, costi/tempi per livello, tech level, requisiti di risorsa); le unita' hanno condizioni su edificio, fazione, regione, cultura e periodo (dati sufficienti per un ricostruttore 1:1).
3. Non c'e' una colonna "popolazione": il solo valore economico base della regione e' `income` (rendita annua da raccolto, 110-897, somma 44.490, media 416) in `SetAttributes`; i miglioramenti agricoli aggiungono +120/+140/+160/+180 (colonna reddito di IMPROVED_FARMLAND).
4. I trigger degli eventi storici, dei disastri, di Mongoli/Peste/Crociate/Jihad e le soglie delle invenzioni NON sono nei file: solo testi (Events.txt) e date di calcolo dei Glory Goals scritte in italiano dentro `glorygoals.txt`. Le invenzioni sono solo nominate (colonna 26 edifici, ora azzerata da Auror).
5. I file attuali sono pesantemente alterati da Auror (164 righe marcate `MOD Auror` nello startpos, 4 regioni nordiche agli Auror, 175 unita' con FN_DANISH, ...). L'originale XL non e' fornito: serve l'installer XL (`VH_MTW_XL3_Full.exe`) o i backup `_BACKUP_PRE_XL`/`_MOD_BACKUP_ORIG` citati dal LEGGIMI ma assenti dall'upload.

Script/CSV prodotti: `tools/tsvload.py` (parser TSV virgolettato), `tools/decode_lbm.py`, `tools/lbm_regions.py`, `tools/lbm_adjacency.py`, `tools/extract_tables.py`; CSV in `out/`: `regions.csv` (107), `units_early.csv` (256), `buildings_early.csv` (46), `factions.csv` (31), `adjacency_bitmap_R3_min100.csv`, `adjacency_compare.json`, `lukmap/preview.png`.

## 1. File per file: scopo, formato, chiave, relazioni

| File | Scopo | Formato | Chiave | Relazioni |
|---|---|---|---|---|
| `campmap/startpos/EARLY_XL.TXT` (4146 righe) | Stato iniziale della campagna Early XL: dichiarazioni, mappa, economia, fazioni, personaggi, edifici, eserciti | Righe `Comando:: arg arg ...` (spazi/tab), `//` commento. Vedi sez. 2 | Token `FN_*` (fazione), `ID_*` (regione) | Punta ai prod (riga 52), ai nomi (668), ai testi region/faction specific (674, 680). Le altre due epoche (HIGH_XL, LATE_XL) e le campagne vichinghe NON sono fornite |
| `MTW_XL_EARLY_UNIT_PROD11.TXT` / `..LATE..` | Definizione unita', agenti, navi, cavalcature | TSV, 52 colonne, header di 3 righe multilinea (celle tra `"`) + riga `DATA START` (riga 20) poi 256 record | Colonna 0 (nome, univoco; serve anche a trovare i file grafici) | col. 28/29/11/12/32 usano `FN_*`, `ID_*`, culture; col. 16 usa token edificio del file edifici; testi in Descriptions.txt (`<Nome>_desc`) e tooltip labels (col. 24) |
| `MTW_XL_EARLY_BUILD_PROD13.TXT` | Edifici con livelli | TSV, 28 colonne, header riga 1-3, `DATA START` riga 4, 46 record (uno per famiglia, i livelli sono liste separate da virgola nella stessa cella) | Colonna 1 (nome famiglia); il livello n si cita come `NOME` (n=1), `NOME2`, ... | Citato da MakeBuilding (startpos) e dalle colonne 16 delle unita'. Esistono anche HIGH/LATE (non forniti, dedotto da `auror_apply.py`, funzione `build_file` su EARLY/HIGH/LATE) |
| `campmap/names/MTW_XL_EARLY_HEROES.TXT` (4374 righe) | Liste nomi (nomi, cognomi, principesse, ribelli), re famosi, eroi | Parole chiave `X::` poi righe dati; il file ha le regole in commento (righe 1-42) | Faction token | Indici in `ADD_*` (ordine di creazione, base 1); nomi devono esistere in Loc/names.txt |
| `CMAPCOORDS_INTERSECT.TXT` | NON e' dati: documentazione C++ di un `MC_INTERSECT` (Dan T, 18/6/01) con funzioni geometriche (intersezione segmento/vettore). Utile solo come conferma che esistono coordinate float x/z sulla mappa strategica | testo | - | Nessuna: da ignorare per il dizionario |
| `Z_Stats.Txt`, `ZStrat.TXT` | `Z_Stats`: stringhe francesi delle statistiche di fine partita (re col regno piu' lungo, assassinii, battaglie, epidemie, ecc., tutti a 0). `ZStrat`: log del driver grafico (`Total 134217728`, `Tex Depth 16`, ...) | testo | - | Non servono ai dati; Z_Stats elenca le statistiche tracciate dal gioco (riga 1-199) |
| `Textures/campmap/LukMap.Lbm`, `LUKUPMAP.LBM` | Bitmap di lookup regioni (identiche) | IFF PBM 8 bit, ByteRun1 | Indice palette | Sez. 8 |
| `Loc/Italian/*.txt` | Testi: `["etichetta"]` poi `{"testo"}` su riga successiva; array con prefisso `@` (`@["arr"]` + `@{"..."}`) | cp1252 | Etichetta | Sez. 5 |
| `_XL_LEGGIMI/reademe_xl.txt`, `_MOD_DANESI_LEGGIMI.txt`, `_MOD_BACKUP_ORIG/auror_apply.py` | Documenti | testo/py | - | Sez. 10 |

## 2. EARLY_XL.TXT: comandi e argomenti

Il file ha commenti `//` ufficiali che spiegano le regole base. Regole citate: gli ID fazione/regione sono assegnati nell'ordine di dichiarazione (righe 61-80, 122-137); faccia 0 = ribelli; ogni token deve essere dichiarato prima dell'uso; un SetNeighbours accetta max 15 vicini (riga 683-689: oltre 15 vicini "Medieval will crash"); le regioni vanno dichiarate prima degli edifici (righe 1865, 2985); se un capo di una fazione attiva non viene piazzato la fazione muore dopo il primo turno (righe 2830-2835).

| Comando (righe) | Argomenti | Note / esempio | Num. |
|---|---|---|---|
| `cn_predefined`, `cn_title`, `cn_short_title` (5-7), `cd_predefined`, `cd_line` (13-15), `cd_hidden` (21) | bool / testo o etichetta | Titolo e descrizione campagna; `cd_hidden` = non appare nelle battaglie personalizzate | 1 |
| `SetStartDate` (30) | anno | 1000 (Auror; XL originale 1080 per README 3.0) | 1 |
| `SetPeriod` (31) | EARLY/HIGH/LATE | periodo di partenza | 1 |
| `SetEarly/High/LatePeriodStartDate` (32-34) | anno | 1000 / 1205 / 1321. Soglie in cui scattano le epoche (dedotto: periodi dei prod) | 3 |
| `Prodfiles` (52) | `UNITPROD "file" BUILDINGPROD "file"` | file nella cartella radice del gioco (riga 46-47) | 1 |
| `DeclareFaction` (84-114) | `"FN_X"` | ordine = ID | 31 |
| `DeclareLandRegion` (140-246) / `DeclareSeaRegion` (260-295) | `"ID_X"` | ordine = ID; i mari proseguono la numerazione | 107 / 36 |
| `SetRegionUnfloodable` (304-315) / `SetRegionUnquakeable` (324-400) | `ID` | regioni immuni a inondazioni / terremoti (esistono quindi disastri hardcoded) | 12 / 77 |
| `SetFactionMusic` (412-442) | fazione, 0-3 | 0 arabo, 1 occidentale, 2 vichingo, 3 XL (riga 405-407) | 31 |
| `SetRegionRebels` (454-560) | regione, indice 0-92 | indice nell'array `rebel_factions_xzy` (Loc FACTION_SPECIFIC riga 318, 93 voci: "the Alans", "the Alsatians", ...) | 107 |
| `PortraitsOverride` (574-575) | fazione, cartella | Lithuanians->"Catholic", Volga->"Pagan" | 2 |
| `GGConquestReward` (586-616) | fazione, moltiplicatore | punti gloria per conquista: 0 (ribelli) ... 1.5 (Boemi, Irlandesi, Norvegesi); Danesi 1.0 | 31 |
| `DeclareTradegoods` (623-646) | `"MERCE" n` | n in {15, 20, 80}: significato non scritto (dedotto: valore/prezzo base: 80 = merci di massa (miele, sale, grano...), 15-20 = di lusso) | 24 |
| `SetImportPercentage` (653) | % | 80: % del valore dell'esportazione riconosciuta alle importazioni (commento riga 649-650) | 1 |
| `SetCastleFlagPos`, `SetCastleSelectorPos` (661-662) | coppie x y per 5 livelli | solo grafica | 2 |
| `SetNameData` / `RegionSpecificFile` / `FactionSpecificFile` (668/674/680) | percorso | vedi sez. 5 | 3 |
| `SetNeighbours` (690-833) | `ID ID_vicino ...` (anche mari) | simmetrico (0 asimmetrie verificate), 143 righe (107+36); max vicini 11 (STRAITS_GIBRALTAR, che ripete ID_ATLANTIC_COAST due volte) | 143 |
| `SetBorderInfo` (842-1367) | `da a x y n clima architettura costa/interno vista fiume` | 526 righe = una per coppia ORDINATA (318 coppie non orientate). Il commento di intestazione (riga 840-841) e' disallineato. x,y in unita' mappa (/16 = pixel LukMap: 464/526 entro 12 px dalla coppia di regioni). n (0 in 510 righe, 3,4,5,7,11,13,15 in 16, solo Scandinavia) = ignoto. clima in {LUSH, ARID, TEMPERATE, SAND_DESERT, ROCK_DESERT}, architettura {AT_WESTERN/EASTERN/SOUTHERN_EUROPEAN, AT_ISLAMIC}, vista {FLAT, PLAINS, HILLY, MOUNTAIN, FLT2HLL, HLL2FLT, HLL2MNT, MNT2HLL, FLT2MNT, MNT2FLT}. Serve solo a scegliere la mappa di battaglia (dedotto) | 526 |
| `SetCastle` (1378-1484) | regione x y | posizione del castello sulla mappa strategica | 107 |
| `SetOrigin` (1494-1636) | regione x y | punto verso cui convergono i pezzi che entrano nella regione (commento 1488-1490) | 143 |
| `SetPort` (1649-1719) | regione x y orientamento | senza SetPort la regione non puo' avere porto (commento riga 1645); orientamento 0-7 (dedotto) | 71 |
| `SetNumCastleMapGroups` (1733) | n | 4 gruppi mappe assedio | 1 |
| `SetAttributes` (1755-1861) | `ID "Nome" rebellious cultura terreno architettura mapgroup income "castello" costa/interno vista fiume vittoria` | vedi tabella sotto | 107 |
| `SetCastleMap` (1882, commentata) | regione + coppie livello "mappa" | mappe d'assedio speciali, inutilizzato | 0 |
| `SetResources` / `SetTradableGoods` (1907-2010) | regione + lista token | Risorse (richiedono edificio per sfruttarle, commento 1894-1897) / merci (sfruttabili subito, commento 1899-1903). Piu' righe per stessa regione possono coesistere (gotcha) | 33 / 71 righe (70 regioni) |
| `SetActiveFaction` (2019-2048) | fazione, `FT_MAJOR` | solo FT_MAJOR in uso (giocabile); altri tipi non presenti nel file | 27 |
| `SetTreasury` (2063-2092) | fazione, 4 valori | EASY NORMAL HARD EXPERT (commento 2054-2059); default 2000 se omesso; standard 10000/8000/6000/4000; Irlandesi 12000/10000/8000/6000; Auror 99999 | 29 |
| `SetCulture` (2099-2129) / `SetReligion` (2135-2165) / `SetBehaviour` (2196-2226) | fazione, token | culture: CATHOLIC, ORTHODOX, MUSLIM, PAGAN (_CULTURE); religioni REL_CATHOLIC/ORTHODOX/ISLAMIC/PAGAN; comportamenti AI elencati nel commento 2170-2195 (CATHOLIC_EXPANSIONIST, ... POPE, BARBARIAN_RAIDER, REBELS) | 30 |
| `SetShieldImage` (2238-2270) | fazione, grande, piccola, nome scudo GA, 2 flag | file BIF in campmap/shields (formato noto) | 31 |
| `SetFactionCol` (2274-2304) | fazione, RGB, RGB | due colori (principale/secondario) | 30 |
| `SetRegionOwner` (2316-2431; commentate 2436-2476) | regione fazione | senza riga = ribelli. I mari non si assegnano | 85 attive |
| `AddTitle` (2491-2607) | regione "titolo" lealta' acume terrore guerra pieta' vizio virtu' | titolo di governatore con bonus al generale (colonne dedotte dal commento 2487). Il commento cita un campo "description" non presente nei dati. Alcuni titoli vuoti `""` (2605-2607) | 107 |
| `AddOffice` (2618-2826) | fazione edificio "nome" + 7 valori | carica sbloccata da un edificio unico (palazzo reale, cancelleria, ...). 180 = 30 fazioni x 6 edifici (ROYAL_PALACE, CONSTABLES_PALACE, MARSHALS_PALACE, CHANCELLERY, ADMIRALTY + CATHEDRAL o GRAND_MOSQUE) | 180 |
| `SetStartLeader` (2837-2866) | fazione + numeri | vedi sez. 6 (Personaggio) | 27 |
| `PlaceLeader` (2868-2897) | regione fazione | | 27 (2+2 commentati) |
| `AddHeir` (2899-2981) | fazione sesso/flag eta' | es. `AddHeir:: FN_ALMOHAD 1 13` (dedotto: 1 = maschio, eta') | 76 (+6 commentati) |
| `MakeBuilding` (2993-3632) | regione token_edificio | vedi sez. 6 | 534 |
| `MakeUnit` (3643-4137) | regione unita' n_uomini [uccisioni] | commento riga 3641. Per EMISSARY e PRINCESS il terzo valore e' l'ANNO DI NASCITA (es. 994) | 373 (+3 commentate) |

SetAttributes: colonne reali (dedotte da riga 1755+): 1 `ID`, 2 nome mostrato, 3 REBELLIOUS (0 in 101 regioni; 1 in Khazar e Lesser Khazar; 2 in Estonia, Livonia, Prussia, Pomerania: tutte aree pagane, dedotto), 4 cultura (CATHOLIC 55, ORTHODOX 22, MUSLIM 20, PAGAN 10), 5 terreno (LUSH 42, ARID 41, TEMPERATE 13, ROCK_DESERT 7, SAND_DESERT 4), 6 architettura, 7 mapgroup (-1 = casuale, sempre -1), 8 income, 9 nome castello (label in Loc/names.txt), 10 INLAND/COAST, 11 vista, 12 RIVER/NO_RIVER, 13 condizione di vittoria (TRUE in tutte e 107: la regione conta per le "40 regioni", dedotto da label `40_Region_Victory`). Il commento di intestazione (righe 1742-1752) parla anche di `pop`: NON esiste colonna popolazione.
Anomalia: riga 1846 (Sweden) ha `HILLY` al posto di INLAND/COAST.

## 3. Prod unita' (`MTW_XL_*_UNIT_PROD11.TXT`): colonne

Parser: `tools/tsvload.py` (modulo `csv` con `delimiter='\t'`). Le celle con a capo sono tra `"`. 256 record, 52 colonne. Colonne con dati reali (le altre sono vuote o legacy Shogun: "Dojo", "samurai"):

| Col | Significato (header riga 1-3) | Tipo / valori | Esempio |
|---|---|---|---|
| 0 | Name/Identifier, univoco | etichetta | `Spearmen` |
| 1 | Unit type | INFANTRY, CAVALRY, ARTILLERY, SHIP, MOUNT + 14 tipi agente | `SHIP` |
| 2 | Cost (fiorini) | int | Spearmen 150; Carrack 1500; fanteria 50-750 (media 294), cavalleria 125-850 (media 380) |
| 3 | Support cost (per stagione) | int | fanteria 2-15 (6), cavalleria 6-25 (14); agenti 0 |
| 4 | Production time (stagioni) | int | 1 quasi sempre; artiglieria/navi 2-3; Crusade 4 |
| 5 | Starting honour handicap | int | 0 (248), 1 (5), -1 (3) |
| 6 | Units base strength | int | 80 (197), poi 1/16/20/145/1000 (agenti e navi). Uso di gioco non chiaro |
| 7 | Numero uomini (valore base prima dello scaling) | int | fanteria 12-100, cavalleria 20-60, nave/agente 1 |
| 8 | Honour step: uccisioni per salire di livello | 1, 2, 3 | |
| 9 | General candidate? | PREFERRED/OK/DISCOURAGED | 81/80/95 |
| 10 | Rebel troop mixes | `GRUPPO(peso), ...` | `CATH_REBELS(15), ...` (le unita' possono comporre eserciti ribelli) |
| 11 | Ruler ID troop advantage | `FN_X` | sconto per quel sovrano (dedotto da header riga 3) |
| 12 | Region ID troop advantage | `ID_X` | sconto per regione (es. TeutonicKnights -> ID_PRUSSIA) |
| 14 | Unit choices (AI) | `COMPORTAMENTO(peso)` x 20 | pesi per profilo AI (POVERTY_STRICKEN ... CLOSE_TO_SUPPORT_LIMIT) |
| 16 | Buildings needed to produce | `{A, B}` = AND; `{{A},{B}}` = OR (come negli edifici) | `{ CHAPTER_HOUSE, HORSE_BREEDER3 }` |
| 17 | Unit class (AI/formazione) | liste: ATTACKER, DEFENDER, AMBUSH, MISSILE, CAVALRY, SPEAR, STRONG, ANTI_MISSILE, ANTI_SPEAR, ANTI_CAVALRY, CASTLE_DEFENDER | |
| 18 | Moral bonus | int (-4..10), 207 vuoti | |
| 19 | Periodi applicabili | ALL_PERIODS (162), HIGH+LATE (41), EARLY (26), LATE (13), EARLY+HIGH (10), HIGH (3) | |
| 20 | Dimensione scalabile | YES/NO | |
| 21 | Stats | `CHIAVE( n )` x 22 (stesse chiavi in 223 unita'): HEIGHT, RADIUS, SCALE, PROJECTILE_TYPE, SAMURAI, MARCH/RUN/CHARGE_SPEED, MIN/MAX_TURNSPEED, TURN_TO_MOTION_SPEED, MAX_INMOTION_TURN, FORMATION_WIDTH/LENGTH_SPACING, ENGAGEMENT_THRESHOLD, **CHARGE_BONUS, MELEE_BONUS, DEFENCE_BONUS, ARMOUR_LEVEL, HONOUR_LEVEL, AMMO**, FORMATIONS_PREFERRED_NUM_ROWS | Spearmen: CHARGE 5, MELEE 0, DEFENCE -1, ARMOUR 1, HONOUR 2 |
| 22 | Invisibile in mappa strategica | YES (spie/assassini) / NO | |
| 24 | Tooltip labels | 4 etichette Loc | `own_unit_tooltip1,...` |
| 25 | Mount type | HORSE (81), CAMEL (2), vuoto | |
| 26 | Corpo/colore/hires/cavalcatura | `CUSTOM0, YES, YES` | solo grafica |
| 27 | Se capo di una fazione: fazione | `FN_X, ...` | solo 17 unita' (RoyalKnights, Kataphraktoi, Boyar, ...): sono le unita' del generale (re) per periodo (header riga 2) |
| 28 | Faction association | `ALL_FACTIONS` o lista `FN_X` (secondo livello di filtro) | 175 militari con FN_DANISH (Auror) |
| 29 | Regione (OR) | `ID_X, ...` | unita' regionali; 46 militari. Auror ha aggiunto ID_DENMARK/SWEDEN/NORWAY/SCANIA a tutte |
| 30-31 | Formazione/suitability (31 "non piu' usato") | | solo battaglia |
| 32 | Culture (escludenti) | `CATHOLIC, ORTHODOX, MUSLIM, PAGAN` | esclude le altre culture dalla produzione |
| 33 | Dati nave | `portata, attacco, difesa, velocita', forza, etichetta` | Carrack `3,6,3,3,0`; Dromon `1,1,0,4,0` (header riga 3: "Range, Attack, Defence, Speed, Strength") |
| 34-42 | Supporto file, disciplina, ordine, scudi, anti-corazza, bonus/difesa vs cavalleria | solo battaglia | |
| 43-45 | Unita' temute, effetto su zelo/fede delle religioni | `PAGAN(0), CATHOLIC(2), ...` | Inquisitor +2 cattolici, GrandInquisitor +5, Ulama +2/5 |
| 46-47 | Smonta in X / smonta in campo aperto | nome unita' | HorseArchers -> Archers |
| 48 | Tipo arma | SWORD/SPEAR/AXE/CLUB | |
| 49 | Mercenario | YES (105) / NO | usa col. 50-51 |
| 50-51 | Periodo e fazioni per battaglie personalizzate | **valori ORIGINALI non toccati da Auror per le fazioni** (col. 51) e per i periodi (col. 50) | Carrack: col. 50 = LATE e col. 51 = 11 fazioni; col. 19/28 = ALL_PERIODS/FN_DANISH (Auror). Utile per ricostruire gli originali |

Agenti (record 268-282, riga 268 = Carrack, 269 = Spy ...): Spy (100, edificio BROTHEL o NEW_BROTHEL), Assassin (200, TAVERN/NEW_TAVERN), Emissary (100, ROYAL_PALACE), Princess (0, nessun edificio: nasce con la famiglia), Bishop (100, CHURCH), Cardinal (150, CATHEDRAL), Inquisitor (200, MONASTERY), GrandInquisitor (300, RELIQUARY, HIGH+LATE), Priest (100, CHURCH), Shaman (100, PAGAN_SHRINE), OrthodoxBishop (150, CATHEDRAL), Mullah (100, MOSQUE), Ulama (150, GRAND_MOSQUE), Crusade (1000, 4 stagioni, CHAPTER_HOUSE), Jihad (500, 2 stagioni, RIBAT).

EARLY vs LATE: stessi 256 nomi nello stesso ordine; differiscono 89 liste fazioni (col. 28), 80 col. 51, 13 edifici (col. 16: ordini cavallereschi XL richiedono ROYAL_COURT3/ARMOURER3 in LATE), 10 stats, 8 capi-fazione, 7 regioni. LATE usa 5 token fazione NON dichiarati nello startpos Early: `FN_BULGARIANS, FN_CRUSADERS, FN_TEUTONIC, FN_BURGUNDIAN, FN_HOSPITALLER` (dedotto: dichiarati nelle campagne XL HIGH/LATE, non fornite; README XL: fazioni Bulgari, Crociati, Ordine Teutonico, Ospitalieri, Burgundi). Il file EARLY non ha token non dichiarati.

## 4. Prod edifici (`MTW_XL_EARLY_BUILD_PROD13.TXT`): colonne

Ogni record = una famiglia; i valori per livello sono liste separate da virgola, lunghe `livelli` voci (col. 0 = numero di upgrade = livelli-1). Token di livello: `CASTLE` (1), `CASTLE2`, ... `CASTLE15`.

| Col | Significato | Note |
|---|---|---|
| 0 | Numero di upgrade | `lv = n+1` |
| 1 | Nome/ID (univoco) | `CASTLE`, `BOWYER` ... |
| 2 | Nome localizzato per livello | stringhe (poi in Loc/names.txt e Descriptions.txt) |
| 3 | Tipo | CASTLE, TROOP_PRODUCER, AGENT_PRODUCER, NON_PRODUCER, SHIP_PRODUCER, PORT, TRADING_POST, FARM_INCOME, LEV1_INCOME (miniere), CATHEDRAL_INCOME, UNIQUE |
| 4 | Costo per livello (fiorini) | CASTLE: 400,100,100,1000,... 8000,1000,1000 |
| 5 | Tempo di costruzione (stagioni) | CASTLE 4,1,1,8,...,10,10 |
| 6 | Condizioni per livello | `{}` nessuna; `{A,B}` = AND; `{{A},{B}}` = OR (dedotto da `ARMOURER` livello 1: `{{CASTLE4,BOWYER},{CASTLE4,SPEARMAKER}}`) |
| 7-8 | Infopic / pezzo mappa | grafica |
| 9 | Preferenze produzione AI | `COMPORTAMENTO(peso)` |
| 10 | Influenze AI per combinazioni | `{IMPROVED_FARMLAND(50)}` |
| 11 | Edificio "di frontiera" | YES solo WATCH_TOWERS |
| 12-13 | Vantaggio di sovrano / sconto | vuote |
| 14 | Religione | CATHOLIC, ORTHODOX, MUSLIM, PAGAN o liste |
| 15 | Bonus lealta' | sempre vuoto |
| 16 | Potenziamento truppe | `UPGRADE_ARMOUR(1..4)`, `UPGRADE_WEAPON`, `UPGRADE_VALOUR`, `UPGRADE_MORALE(1..3)`, `UPGRADE_DISCIPLINE` |
| 17 | Tech level | CASTLE `0,0,0,1,1,1,2,2,2,3,3,4,4,4,4`; ALTRI 1-5 |
| 18 | Risorsa richiesta nella regione | `{ IRON }` METALSMITH; `{ COPPER }`, `{ SILVER }`, `{ GOLD }`, `{ SALT }` miniere |
| 19 | Fazioni ammesse per livello | vuoto = tutte; GUNSMITH liv.1 `{FN_EGYPTIAN, FN_DANISH}` (originale: solo Egiziani, dedotto) |
| 20 | Glory goal collegato | CASTLE liv.10: KRAK_DES_CHEVALIERS, ALHAMBRA_PALACE; liv.13: KREMLIN; UNIVERSITY: JAGELLONIAN; RELIQUARY: SAINTE_CHAPELLE; CATHEDRAL: NOTRE_DAME, FLORENCE_DUOMO; GRAND_MOSQUE: GRAND_MOSQUE_AL_AZHAR |
| 21 | Propagazione della fede | 0.1 - 0.15 (CHURCH, MOSQUE, CATHEDRAL...) |
| 22 | Reddito generato | IMPROVED_FARMLAND 120/140/160/180; CATHEDRAL e GRAND_MOSQUE e PAGAN_MONUMENT 100; HOSPITAL 75; miniere rame 100/200, argento 150/300, oro 200/400, sale 50/100 |
| 23 | Aggiustamento felicita' della popolazione | 10-40 |
| 24 | Mercenary magnetism | CASTLE -10..-40; INN 40; CONSTABLES/MARSHALS -10 |
| 25 | Ritrovo di mercenari | YES: INN |
| 26 | Invenzioni richieste | `NONE` in GUNSMITH, SHIPYARD, FOUNDRY (Auror): originale ignoto (polvere da sparo, bussola da LEGGIMI riga 32 Auror) |
| 27 | Capacita' unita' (guarnigione) | solo CASTLE: 240..960 (fanteria; meta' cavalleria, Loc `castle_size_txt_xzy`) |

Famiglie (46): CASTLE(15), BOWYER, ARMOURER, SWORDSMITH, METALSMITH, SPEARMAKER, SIEGE_ENGINEER, GUNSMITH, TOWN_WATCH, MERCHANT (4 ciascuna), INN, TAVERN (vecchia, solo FN_REBEL), BROTHEL (idem), ROYAL_PALACE, CHANCELLERY, CONSTABLES_PALACE, MARSHALS_PALACE, ADMIRALTY, UNIVERSITY, COLLEGE_OF_SURGEONS, MILITARY_ACADEMY, HOSPITAL, IMPROVED_FARMLAND(4), HORSE_BREEDER(4), ROYAL_COURT(4), CHURCH, MOSQUE, MONASTERY, RELIQUARY, CATHEDRAL, GRAND_MOSQUE, PAGAN_MONUMENT, CHAPTER_HOUSE, RIBAT, WATCH_TOWERS(2), PORT, SHIPYARD(4), FOUNDRY(3), COPPER/SILVER/GOLD/SALT_MINE(2), NEW_TAVERN(4), NEW_BROTHEL(3), PAGAN_SHRINE(2), MUSTER_FIELD (solo FN_REBEL). Totale 112 livelli.

## 5. Altri file di dati

**`MTW_XL_EARLY_HEROES.TXT`** (regole righe 1-42; sezioni): `SET_FORENAMES:: FN lista n_nomi_reali` (46-75: es. DANISH `2 1`: lista 2, solo il 1o nome e' "reale"); `SET_SURNAMES:: FN lista` (77-105); `SET_PRINCESS:: FN lista` (107-133); `SET_REBELS:: ID_regione lista_nomi lista_cognomi` (135-241); `FAMOUS_KINGS:: FN n` (243-499; 30 fazioni, una riga per re: `nome_idx, numero, c, d, p, a, ritratto, vnv`); `FAMOUS_HEROES:: FN n` (507-790; 24 fazioni, 218 eroi: 155 GENERAL, 22 EMISSARY, 22 BISHOP, 16 INQUISITOR, 2 CARDINAL, 1 ASSASSIN; date di comparsa 1024-1441; riga: `"nome","cognome", anno, c,d,p,a,l, vnv, TIPO, ID_REGIONE|ID_LIMBO, ritratto`); `ADD_FORENAMES::` (33 liste, righe 804-2517, numerate da 1 in ordine di creazione), `ADD_SURNAMES::` (24 liste, 2628-3897), `ADD_PRINCESS::` (17 liste, 4005-4348): ogni voce `"Nome"` deve esistere in Loc/names.txt. Attributi: dall'intestazione c=comando, d=terrore (dread), p=pieta', a=acume, l=lealta' (nomi dedotti: le sigle sono nelle righe 245-246 e 509; il significato lo conferma `Events.txt generals_attrib_*`). `vnv` = tratto vizio/virtu' (`defender3`, `educated1`, `secret_paranoiac3`, ...: 85 tratti distinti usati da re/eroi; ~240 etichette `<tratto><n>title` in Events.txt, effetti NON nei dati). Ricerca: `Auror` assente qui, solo `Darkos` (1 occorrenza).

**`Loc/Italian/`** (tutti: `["label"]` + `{"testo"}`; `@[..]` = array indicizzato per posizione; `%s`/`%d` = segnaposto):
| File | Righe/etichette | Contenuto |
|---|---|---|
| `Events.txt` | 5515 / 1730 | messaggi di gioco: finanze, successione, tasse, assedi, spionaggio, tratti vizi/virtu', crociate/jihad/papa, disastri (`floodregmes_xzy`, `famineregmes_xzy`, `plagueregmes_xzy`, `black_plagueregmes_xzy`, `earthquakems_xzy`, `taifunms_xzy`), `Historical_event_titles/text` (5078/5151: 71 + 71 voci) |
| `variables.txt` | 1070 / 54 | testi titoli/uffici, obiettivi di battaglia, finanze, array `factions_special_xzy`... (2 occorrenze "Auror") |
| `names.txt` | 6783 / 5129 | nomi propri, nomi regioni (`country_xzy`, riga 44; voce 0 "Region Zero"), castelli, edifici, tre "Free" slot fazione |
| `global.txt` | 310 / 93 | UI generale |
| `Descriptions.txt` | 1918 / 834 | descrizioni unita' (`<Unit>_desc`) ed edifici |
| `startpos.txt` | 689 / 110 | `Era_Description_EARLY/HIGH/LATE` (+ `_XL`), `FSM_faction_info_faction_<FAZ>_<PERIODO>` (101) |
| `glorygoals.txt` | 758 / 236 | testi dei Glory Goals (in ITALIANO, originali del gioco); 181 obiettivi distinti |
| `MTW_XL_EARLY_REGION_SPECIFIC.TXT` | 1578 / 12 array | array per regione (144 voci = 1 "Region Zero" + 107 + 36): `country_xzy`, `province_of_xzy`, `pl_invasion_title_xzy`, `region_taken/lost/return_title_xzy`, `Amir_of_String`, `Duke_of_String`; 31 `of_Clan_Districts`; `goods_names` (24), `tradable_goods_intro_tooltips` (24), `castle_size_txt_xzy` (15) |
| `MTW_XL_EARLY_FACTION_SPECIFIC.TXT` | 479 / 10 array | `faction_leaders_xzy`, `king_titles`, `factions_xzy`, `factions_posessive_xzy`, `female_factions_posessive_xzy`, `factions_special_xzy`, `custom_battle_menu_factions`, `of_Clan_Names` (31 voci, in ordine di dichiarazione), `rebel_factions_xzy` (93) |

I testi XL (nuove unita', fazioni, eventi) sono in INGLESE dentro `Loc/Italian`; i testi base del gioco sono italiani.

## 6. Entita' del dominio

**Fazione** (30 + ribelli). Definita in `DeclareFaction` (ID = ordine). Attributi: attiva (SetActiveFaction), cultura, religione, comportamento AI, tesoro x 4 difficolta', colori, scudo, musica, moltiplicatore GG, ritratti, capo (SetStartLeader + PlaceLeader), eredi (AddHeir), cariche (6 AddOffice), nomi (SET_*), 17 unita' leader (col. 27 unit prod), testi (faction specific). Relazioni: 1:N regioni (SetRegionOwner), N:M unita'/edifici (liste fazione nei prod). Nome mostrato != ID: `FN_ALMOHAD` = "The Almoravids" (Loc), `FN_EGYPTIAN` = Fatimidi, `FN_TURKISH` = Selgiuchidi, `FN_RUSSIAN` = Kievani, `FN_ITALIAN` = Veneziani, `FN_PAPIST` = Papato, `FN_VOLGA` = Bulgari del Volga, `FN_DANISH` = "The Auror" (Auror).
Tabella (da `out/factions.csv`): regioni iniziali per fazione: German_HRE 12, Byzantine 10, Turkish 8, Almohad 5, Danish (Auror) 4, Egyptian/English/French/Cumans/Genoese 4, Polish/Sicilian 3, Italian/Spanish/Russian/Hungarian/Papist 2, 12 fazioni da 1. Capitali (PlaceLeader): Almohad Cordoba, Byzantine Nicaea, Egyptian Sinai, English Wessex, French Ile-de-France, HRE Austria, Italian Venice, Polish Poland, Russian Kiev, Spanish Castile, Turkish Armenia, Papacy Papal States, Sicilian Malta, Cumans Levidia, Irish Ireland, ... Fazione inattiva ma dichiarata: Golden Horde (PAGAN, `BARBARIAN_RAIDER`, nessuna regione, nessuna riga SetActive/Leader): serve a un'invasione hardcoded (dedotto da Events `No more money mongols_xzy`, Descriptions Mongols).

**Regione/Provincia** (107 terra + 36 mare): `DeclareLandRegion`/`SetAttributes` (riga 1755)/`SetCastle`/`SetOrigin`/`SetPort`/`SetRegionRebels`/`AddTitle`/`SetNeighbours`/`SetBorderInfo`/`SetResources`/`SetTradableGoods`/`MakeBuilding`. 1:N edifici (534 righe: Auror 137 in 4 regioni; le altre 103 regioni 397, media 3,9), 1:N unita' (MakeUnit), N:M vicini. Il nome mostrato puo' differire dall'ID: `ID_AFRICA` = "Mesopotamia", `ID_LIBYA` = "Cyrenacia" (castello "Libya Castle"), `ID_POLAND` = "Lesser Poland", `ID_GREAT_POLAND` = "Greater Poland", `ID_NORTH_UMBRIA` = "Northumbria", `ID_FREISLAND` = "Friesland". Nel testo dei glory goals `GG_AFRICA` e' ancora "Africa" (non rinominato).

**Edificio**: vedi sez. 4. 1 famiglia : N livelli; MakeBuilding usa il token del livello. Edifici unici (UNIQUE): CHANCELLERY, CONSTABLES/MARSHALS_PALACE, ADMIRALTY, CATHEDRAL, GRAND_MOSQUE, PAGAN_MONUMENT: danno `AddOffice`.

**Unita'**: vedi sez. 3. ID = nome. Relazione: edificio (col. 16), fazione (28), regione (29), cultura (32), periodo (19).

**Personaggio**: (a) Re iniziale: `SetStartLeader:: FN eta?...` - le righe hanno la forma `FN a n v1..vn` con n = numero dei valori seguenti (es. `FN_BYZANTINE 0 7  0 4 7 1 3 10 1`: dopo `0` viene `7` e poi 7 valori; `FN_SICILIAN 0 1 1`). Interpretazione dedotta: il primo `0` e' un flag, `n` e' il numero di nomi reali della lista e i valori sono i contatori di re gia' regnati per nome (ordinali romani). Prova: per Auror lo script scrive `0 1 1` e il LEGGIMI (punti 12, 17) dice "il contatore dei re di nome Darkos parte da 1, quindi Darkos I". (b) Erede: `AddHeir` (sesso/eta'). (c) Generale: nasce in gioco, usa unita' con col. 9 PREFERRED/OK/DISCOURAGED, 5 attributi (comando, terrore, pieta', acume, lealta') + `vnv`; titoli (AddTitle) e cariche (AddOffice) danno bonus. (d) Principessa: `MakeUnit ... Princess <anno_nascita>` (15 righe, 988-992) + lista nomi `ADD_PRINCESS`. (e) Re famosi e eroi: tabelle `FAMOUS_*` (sez. 5), compaiono a data fissa (`date` = anno da cui diventano disponibili) per tipo e regione. (f) Emissari: `MakeUnit ... Emissary 994` (21 righe).

**Agente**: record di prod unita' con tipo agente (sez. 3). Prodotti da edifici AGENT_PRODUCER. Missioni, costi, valore (valour) e probabilita' NON sono nei dati.

**Merce/Risorsa**: merci = `DeclareTradegoods` (24 con n=15/20/80) + `SetTradableGoods` per regione (WOOL 18, SILK 18, WOOD 14, FISH 13, WAX 12, ...); risorse = `SetResources` (IRON 14, SALT 13, COPPER 12, SILVER 12, GOLD 10), sfruttate con edifici (miniere: reddito 50-400). Formula di commercio e valore di vendita NON nei dati (solo `SetImportPercentage 80`).

**Evento**: solo testi (`Historical_event_titles/text` 71; messaggi di disastri; crociata/jihad; eventi Viking righe 5501-5505 vuote). Nessun trigger.

**Obiettivo di gloria (Glory Goal)**: testi in glorygoals.txt: `GG_<NOME>_TITLE`/`_DESCRIPTION` + etichette di condizione + `GG_<REGIONE>` (nome regione, ~100). Le date di calcolo punti sono SOLO nel testo (vedi sez. 7).

**Periodo/Epoca**: EARLY/HIGH/LATE; soglie 1000/1205/1321 (EARLY_XL righe 32-34); XL originale: Early parte nel 1080; in LATE (1321). Le epoche limitano unita' (col. 19) ed edifici/invenzioni.

## 7. Regole e "metriche" presenti nei dati

| Regola | Dove | Valori |
|---|---|---|
| Rendita agricola regione (annua, non aumentata) | SetAttributes col. 8 (righe 1755-1861) | min 110 (Arabia, Norvegia 111), max 897 (Constantinople), somma 44.490, media 416; top: Constantinople 897, Flanders 871, Egypt 845, Castile 806, Tripoli 767. README XL: "Farm Income 30% higher" |
| Reddito da edifici | build col. 22 | farmland 120-180; miniere (rame 100/200, argento 150/300, oro 200/400, sale 50/100); cattedrale/moschea grande/monumento pagano 100; ospedale 75 |
| Costi e tempi di costruzione | build col. 4-5 | per livello (fiorini, stagioni); CASTLE complessivo 400+...: livello 15 costa 1000 e richiede 10 stagioni |
| Requisiti | build col. 6, 17, 18, 19, 26 | prerequisiti edificio (AND/OR), tech level 0-5, risorsa nella regione, fazioni, invenzioni |
| Capacita' guarnigione | build col. 27 (CASTLE) | 240-960; cavalleria = meta' |
| Disponibilita' unita' | unit col. 16, 19, 28, 29, 32 | edificio AND/OR, periodi, fazioni, regioni, culture |
| Costo/mantenimento/tempo/uomini | unit col. 2, 3, 4, 7 | fiorini; per stagione; stagioni; base prima dello scaling |
| Stat per risoluzione automatica | unit col. 21 | ARMOUR_LEVEL (1-9), HONOUR_LEVEL (0-12), CHARGE/MELEE/DEFENCE_BONUS, AMMO, uomini, velocita'; col. 41-42 bonus anti-cavalleria; col. 9 e 17 classe; col. 33 stat navi (portata, attacco, difesa, velocita', forza) |
| Esperienza | unit col. 5, 8 | honour handicap e uccisioni per livello |
| Rebel mix | unit col. 10 | composizione truppe ribelli per tipo (CATH_REBELS, MUS_ZEALOTS, JIHAD, ...) |
| Rebel faction per regione | SetRegionRebels | indice 0-92 su array di 93 nomi |
| Titoli governatore | AddTitle (2491-2607) | lealta' +1/+2, acume, terrore, guerra, pieta' (es. Auror Jarl Denmark +2 lealta', +1 guerra) |
| Cariche | AddOffice (180) | lealta' +1..+3, acume 0-2, guerra 0-2, pieta' 0/3 |
| Punti gloria conquista | GGConquestReward | moltiplicatori 0-1.5 |
| Tasse | solo etichette (`Tax_Punitive/High/Normal/Low/Very Low`, Events) | nessun valore |
| Tesoro | SetTreasury | 10000/8000/6000/4000 e varianti |
| Date calcolo Glory Goals | testo italiano (glorygoals.txt) | es. HOMELAND: 1100,1125,1150,1175,1205,1225,1250,1275,1300,1321,1350,1375,1400,1425,1453 (riga 67); homeland per fazione: 1204/1320/1453; Plantagenet/Valois: 1453; lana/Lega Anseatica: 1250,1300,1350,1400,1450; Alhambra 1205-1320 (58), Kremlin 1367-1377 (338), Notre Dame 1150-1250, Sainte-Chapelle 1230-1260, Hussiti 1410-1440, Duomo di Firenze 1420, Karak 1100-1200, Crociate/Jihad 1095-1204, Costantinopoli 1453. Le CONDIZIONI (province da controllare, edifici, % fede, reddito commerciale 3000/6000/12000/24000) sono in testo, vanno estratte a mano |
| Vittoria | Events labels `40_Region_Victory`, `won_after_40_regions`, `won_all_others_dead` | soglia 40 regioni (dedotto), fine data non presente |

## 8. LukMap.Lbm: decodifica e collegamento alle regioni

Script: `tools/decode_lbm.py` (esegue `python3 -I`), `tools/lbm_regions.py`, `tools/lbm_adjacency.py`. Output in `out/lukmap/` (`index.npy`, `palette.json`, `preview.png`, `region_probe.json`, `adjacency_compare.json`, `adjacency_bitmap_R3_min100.csv`).

- Formato: `FORM....PBM `, chunk BMHD (2048x1536, 8 piani, compressione 1 = ByteRun1, trasparenza 255), CMAP 768 byte, BODY 264299 byte -> 3.145.728 pixel decodificati (corrisponde a 2048x1536). `LukMap.Lbm` e `LUKUPMAP.LBM` hanno lo stesso MD5: sono lo stesso file (uno e' una copia, il nome minuscolo e' quello usato dal gioco, dedotto).
- Indici usati: 251 su 256 (0 e da 2 a 251; 1 e 252-255 mai usati). 0 = nessuna regione/bordo/fuori mappa (194.074 pixel).
- **Collegamento agli ID regione (verificato)**: con `SetCastle x/16, y/16` come pixel, 103 castelli su 107 cadono nell'indice `2*(n+1)` (n = ordine in `DeclareLandRegion`: Scotland=2, North_Umbria=4, ... Savoy=214); 3 cadono nell'indice dispari adiacente (Norvegia 15, Grecia 113, Portogallo 167: stesso `idx>>1`), 1 e' un castello costiero che cade nel mare (Crimea -> 246). Quindi: **regione_terra = (indice>>1)-1**, indici dispari = variante di colore della stessa regione (nella bitmap formano una texture/dither interna: l'indice 2 ha 398 componenti connesse; dedotto: sfumatura per il rendering della mappa). **Mare k = indice 216+k** (216 North_Atlantic ... 251 Atlantic_Coast; un indice per mare, 36 valori): i baricentri corrispondono (216 in alto a sinistra, 221 Mare del Nord ecc.). I 107 indici terra pari usano 2-214, quelli dispari 3-215.
- Coordinate: le coordinate unita' mappa = 16 x pixel (mappa di 32768 x 24576 unita'). Anche `SetBorderInfo` x,y: 464 su 526 entro 12 px da entrambe le regioni della coppia.
- Regioni distinte: 107 terra + 36 mare = 143 (corrisponde a start pos; ogni indice 2..251 e' presente). Le due isole in riquadro magenta (Malta e Rodi) sono regioni dentro un riquadro con bordo a indice 0.
- **Adiacenze dalla bitmap**: (a) solo pixel adiacenti (4-vicini): 208 coppie trovate, 207 corrette ma richiamo 53% perche' le regioni sono separate da un bordo a indice 0 (magenta); (b) con "ponte" di 3 px sui pixel indice 0 e soglia 100 pixel di contatto: 377 coppie, 374 corrette, 3 extra, 14 mancanti (tutte mare-mare strette); soglia 1 pixel: 394 coppie, 387 corrette su 388 di SetNeighbours (richiamo 99,7%), 7 extra. Per tipo (soglia 100): terra-terra 208/208 trovate, 1 extra (VOLGA_BULGARIA-LESSER_KHAZAR); terra-mare 112/112, 2 extra (NICAEA-SEA_MARMARA 5830 px, VALENCIA-GULF_LIONS); mare-mare 54/68 (14 mancanti: stretti tipo Gibilterra, Sidra, Marmara-Mar Nero).
- Affidabilita': ottima per dedurre il grafo terrestre e per verificare lo startpos (accordo 100% sulle terre), non per i passaggi marittimi stretti. **Fonte autorevole = `SetNeighbours` (righe 690-833)**; la bitmap serve per forme/aree/pick del mouse/colorazione, non per le regole. File di prova: `out/lukmap/adjacency_bitmap_R3_min100.csv` (377 righe). Nota: nello startpos manca ogni adiacenza terra-terra con "ponti terrestri" (rimossi da XL: README "Landbridges removed" tranne Scania-Danimarca) e le regioni insulari (Crete, Rhodes, Cyprus, Malta, Sicily, Sardinia, Corsica, Ireland) sono collegate solo a mari.
- `CMAPCOORDS_INTERSECT.TXT`: solo documentazione C++ di `MC_INTERSECT` (posizione float x/z + vettore delta; intersezioni con linee/vettori). Conferma che il motore usa coordinate float sulla mappa ma non fornisce dati. Non c'e' un file con vertici/poligoni delle regioni: la geometria e' solo la bitmap.

## 9. Inventario

| Voce | Numero |
|---|---|
| Fazioni dichiarate / attive / giocabili | 31 (30 + ribelli) / 27 / 27 (tutte FT_MAJOR) |
| Fazioni "slot libero" nei nomi | 26 etichette "Free" in Loc/names.txt (disponibilita' extra, limite 32) |
| Regioni terra / mare | 107 / 36 |
| Regioni con porto (SetPort) | 71 |
| Regioni con castello (SetCastle) | 107; con titolo (AddTitle) 107 |
| Culture regioni | CATHOLIC 55, ORTHODOX 22, MUSLIM 20, PAGAN 10 |
| Edifici: famiglie / livelli / token usati in startpos | 46 / 112 / 64 |
| MakeBuilding iniziali | 534 (Auror 137) |
| Unita' (record) / militari / navi / artiglieria / MOUNT / agenti | 256 / 236 / 13 / 13 / 5 / 15 |
| Unita' per periodo (col. 19, militari) | ALL 143, HIGH+LATE 40, EARLY 26, LATE 13, EARLY+HIGH 10, HIGH 3, vuoto 1 |
| Unita' con edificio di produzione | 213 (23 militari senza edificio: non producibili/solo mercenari o ordini) |
| MakeUnit iniziali | 373 (RoundShieldSpearmen 49, Spearmen 46, HorseArchers 30, Archers 21, Emissary 21, ...) |
| Agenti iniziali | 21 emissari, 15 principesse |
| Eredi (AddHeir) / cariche / titoli | 76 / 180 / 107 |
| Re famosi (FAMOUS_KINGS) | 30 fazioni; 172 re (somma dei contatori) |
| Eroi (FAMOUS_HEROES) | 218 in 24 fazioni |
| Eventi storici testuali | 71 |
| Merci / risorse | 24 / 5 |
| Soglie periodi | 1000 / 1205 / 1321; date di calcolo GG 1095-1453 |
| Soglie di data nei Glory Goals | ~45 date distinte (1095-1453); 51 obiettivi con descrizione, 181 etichette base |

## 10. Dati alterati da Auror (non XL originale)

Origini documentate (LEGGIMI Auror riga per riga + `auror_apply.py`):
| Cosa | Dove nei file attuali | Originale |
|---|---|---|
| Avvio Early al 1000 (XL: 1080) | EARLY_XL.TXT riga 30, 32; anni di nascita Emissary/Princess -80 (righe 4101-4137: 994/988-992; originali ~1074/1068-1072, dedotto dal delta 80) | XL 3.0 originale (installer) |
| Tesoro Auror 99999 | riga 2065 | 10000/8000/6000/4000 |
| Danimarca+Svezia+Norvegia+Scania agli Auror | righe 2316-2319; edifici 2993-3130 circa (137 righe: 38 DENMARK, 33 per le altre); risorse 1907-1909 (IRON COPPER SILVER GOLD SALT), merci 1939,1975,1988,1996,1997 | proprietari originali non nel file: backup `_BACKUP_PRE_XL` / installer |
| Svedesi e Norvegesi eliminati | SetActiveFaction/SetStartLeader/PlaceLeader/AddHeir commentati (2041, 2047, 2859, 2865, 2890, 2896, 2960-2978) | attivi in XL |
| Capo iniziale Auror | riga 2839 `SetStartLeader FN_DANISH 0 1 1` | originale non noto |
| 3 eredi extra (24, 21, 18 anni) | righe 2908-2910 | |
| 3 eserciti (16 unita' ciascuno) + 16 Caracche | MakeUnit con Teutonic/Templar/Feudal Knights, OrderFootsoldiers, HospitallerFootKnights, Arquebusier, CulverinCrew, SiegecannonCrew + 16 `Carrack` (ID_DENMARK) | assenti |
| Unita': FN_DANISH aggiunto a 175 militari (col. 28), ID_DENMARK/SWEDEN/NORWAY/SCANIA alle unita' regionali (col. 29), CATHOLIC aggiunto a culture non cattoliche (col. 32), edifici musulmani/pagani/ortodossi sostituiti (Mosque->Church, Grand Mosque->Cathedral, Ribat->Monastery), armi da fuoco e navi ALL_PERIODS, `Carrack` solo FN_DANISH 1 stagione, ordini cavallereschi con edificio di produzione `CHAPTER_HOUSE + HORSE_BREEDER3/ARMOURER2` | MTW_XL_*_UNIT_PROD11.TXT | col. 50-51 mantengono periodo e fazioni originali per battaglie personalizzate (non toccate) |
| Edifici: FN_DANISH in ogni colonna 19 non vuota; invenzioni `NONE` in GUNSMITH/FOUNDRY/SHIPYARD | BUILD_PROD13 (col. 19, 26) | invenzioni originali sconosciute |
| Re famosi Auror | HEROES: lista nomi 2 (primo nome "Darkos"), `SET_FORENAMES FN_DANISH 2 1`, FAMOUS_KINGS Danish (riga 266: 8 re con `7,9,9,9`), FAMOUS_HEROES Danish (riga 545: GENERAL con `7,9,9,9,9`) | originali danesi non nel file |
| Testi | Loc FACTION_SPECIFIC/variables ("The Auror", "King of the Auror"; 8+2), names.txt `Darkos` | |
| Exe patch (comando 9, immortalita', fedelta' 9, influenza max); intro disattivati; .bat di compatibilita' | non forniti (nell'eseguibile) | `Medieval_TW.exe` originale: verifica integrita' Steam |
| EARLY_XL fix crash | `EARLY_XL_PRE_FIX_CRASH.bak` | non fornito |

Dove sono gli originali secondo i documenti (nessuno e' stato caricato): `_MOD_BACKUP_ORIG\` (originali pre-Auror: nell'upload e' presente solo `auror_apply.py`), `_BACKUP_PRE_XL` (file sovrascritti da XL), `_MOD_AUROR_XL_FILES` (copia dei file della mod), `_XL_LEGGIMI`, installer `VH_MTW_XL3_Full.exe` (sorgente XL), `EARLY_XL_PRE_FIX_CRASH.bak`. Lo script usa un modulo esterno non fornito (`/tmp/tools/tsvspan`) per parsare i TSV preservando offset: il nostro `tsvload.py` e' un sostituto equivalente per la lettura.
Per riscrivere il campo di gioco: ripristinare le colonne tramite le regole dello script (aggiunte per FN_DANISH, token regionali, `ALL_PERIODS` sulle armi da fuoco...) oppure ottenere l'XL originale.

## 11. Trappole (gotchas)

1. TSV: celle tra `"` con a capo interni (header di 3 righe a ~1000 caratteri/cella; in LATE e EARLY le prime 3 righe hanno 52 colonne identiche ma `DATA START` e' alla riga 20 per le unita', 4 per gli edifici). Usare un parser CSV con tab, non `split('\t')`; liste di fazioni con spazi variabili (`FN_DANISH,FN_ARAGONESE`), `Yes/No/YES`, `HIGH,LATE` vs `HIGH, LATE`, `{}` e `{ A }` con spazi.
2. Condizioni edificio: `{A,B}` = AND, gruppo annidato `{{A},{B}}` = OR, token con suffisso numerico = livello (`CASTLE4` = Keep). Il nome del token livello 1 non ha suffisso; CASTLE e' diviso in 5 tier da 3 sottolivelli ("Fort, Fort Motte, Fort Motte Bailey") con la regola OR per il primo livello di ogni tier.
3. Colonna fazione nei prod: lista di fazioni per LIVELLO (build col. 19 `{A},{},{},{B}`), vuota = tutti; per le unita' ALL_FACTIONS o lista e va letta insieme agli edifici ("second level filter", header col. 28). Le liste in LATE includono fazioni non presenti in EARLY.
4. Token non dichiarati: se un prod cita un `FN_*`/`ID_*` non dichiarato nello startpos usato, `auror_apply.py:restrict_declared` li rimuove (il gioco lo richiede). LATE_UNIT cita 5 fazioni non dichiarate nello startpos EARLY (Bulgarians, Crusaders, Teutonic, Burgundian, Hospitaller).
5. Ordine: gli ID sono dall'ordine di dichiarazione: aggiungere un'ID cambia la numerazione e quindi gli indici in `SetRegionRebels`, gli array Loc (`country_xzy`, 1 voce "Region Zero" davanti ai 143 ID) e gli indici di LukMap.
6. I nomi mostrati non corrispondono agli ID (sez. 6): `ID_AFRICA`=Mesopotamia, `ID_LIBYA`=Cyrenacia, `FN_ALMOHAD`=Almoravidi, `FN_EGYPTIAN`=Fatimidi ...
7. `SetAttributes`: riga 1846 con `HILLY` al posto di INLAND/COAST; terreno TEMPERATE e SAND_DESERT non citati nel commento (che elenca solo LUSH, ARID, ROCK_DESERT); colonna `pop` citata ma assente; `REBELLIOUS` e' 0/1/2.
8. `SetResources`/`SetTradableGoods` possono comparire piu' volte per la stessa regione (righe 1907-2010: Auror ha inserito righe all'inizio e rimosso le vecchie; altre regioni hanno righe separate Resources/Goods); il parser deve unire.
9. `MakeUnit`: terzo campo = uomini, ma per Emissary/Princess = anno di nascita; il quarto (uccisioni) quasi mai presente. Numero di uomini 1 per navi/agenti.
10. `SetStartLeader`: formato variabile con lunghezza indicata dal secondo numero; `AddHeir` 0/1 e' un flag (sesso, dedotto).
11. `SetNeighbours`: massimo 15 per riga (crash); STRAITS_GIBRALTAR ha un duplicato; la lista di mare usa gli stessi comandi della terra.
12. I testi XL sono in inglese dentro `Loc/Italian`; i `Glory Goals` sono in italiano e senza XL: l'obiettivo "Kalmar" e "HOMELAND_DENMARK" usano la vecchia geografia. Le etichette `GG_<REGIONE>` non seguono i rinominamenti XL.
13. Date: le date dei prod/GG non sono nei dati, solo nei testi; i tre periodi usano date di inizio 1000/1205/1321 (mod) mentre i GG parlano di 1100/1204/1320/1453. Se la nuova campagna parte nel 1000 e finisce nel 1700, gli obiettivi (1453) e i periodi vanno rimappati.
14. File con commenti: `//` anche dentro righe dati (`MakeBuilding ... // MOD`), e righe commentate con dati ancora utili (rebel lands 2436-2476; Golden Khanate; SetCastleMap).
15. `Z_Stats.Txt` e' in francese, `ZStrat.TXT` e' un log: non sono dati.
16. Le unita' MOUNT (KHorse, ArmHorse...) sono record, non unita' di gioco; non produrle.

## 12. Cosa una campagna richiede e NON e' nei file forniti

(Da cercare nelle meccaniche hardcoded / nell'eseguibile / nei file dati non forniti.)
1. Calcolo del reddito: formule di raccolto/tassazione (livelli di tasse solo come etichette), commercio e prezzi (`DeclareTradegoods` n e `SetImportPercentage` non bastano), costo di mantenimento, bonus alleanza, formula del reddito di CATHEDRAL_INCOME, effetto reale di `FARM_INCOME` sul reddito base.
2. Felicita'/lealta', popolazione, ribellioni e generazione dei ribelli (mix col. 10, ma non quando/come), pagani/eretici/zelanti, propagazione della fede (valori 0.1-0.15 senza formula), eresie, "unrest".
3. Lista delle invenzioni/tecnologie con date e trigger (col. 26 e `LEGGIMI`: polvere da sparo, bussola; `NONE` ora).
4. Eventi storici: trigger, date, effetti, condizioni (71 testi senza dati), disastri (inondazioni, terremoti, carestie, peste, Peste Nera, tifoni: solo testi e liste regioni immuni), invasione mongola/Golden Horde (fazione dichiarata senza territori), Crociate e Jihad (rilascio, partecipazione, obiettivi; solo testi e unita' `Crusade`/`Jihad`), Papa, scomunica, Inquisizione.
5. Punteggio e trigger dei Glory Goals (date solo nel testo italiano, condizioni solo in testo): tutte le condizioni per 51 obiettivi, il peso dei punti, la condizione di vittoria (40 regioni, data finale 1453 solo implicita).
6. Diplomazia, trattati, alleanze, matrimoni (`aa2t_*`, `Treaty` solo testi), IA strategica (behaviours: solo etichette), movimento e attrito, assedi, auto-resolve campagna (solo le stat unita'), morale, saccheggio, schiavitu' di prigionieri/riscatti.
7. Meccaniche dei personaggi: invecchiamento, morte, successione, matrimonio, tratti `vnv` (effetti numerici dei ~250 tratti), vizi/virtu', avanzamento (honour), mercenari (formula), capacita' di comando.
8. Agenti: probabilita' di successo di spie/assassini/emissari/preti, costi missione, tangenti (bribery), infiltrazione, corruzione.
9. Costruzione e addestramento: coda, interazione cantieri/porti, scaling degli uomini (60-120), upgrade truppe (effetto numerico di UPGRADE_ARMOUR/WEAPON/VALOUR/MORALE/DISCIPLINE).
10. Dati XL mancanti: HIGH e LATE (startpos e prod edifici), fazioni Bulgarians, Burgundians, Crusaders, Teutonic, Hospitaller; originali delle regioni Auror; l'intera campagna 1000-1700 (nuova) richiede nuove date di inizio, rimappatura periodi e rinomina GG.
11. Formati: bitmap geometria delle regioni (solo indice, nessun vettore), pathfinding, dimensioni mappa battaglia, formato BIF (noto), audio, eseguibile.
12. Colonne a significato non risolto: `SetBorderInfo` quinto campo, orientamento `SetPort`, `SetShieldImage` ultimi due campi, `DeclareTradegoods` 15/20/80, prod unit col. 6 ("base strength"), `SetFactionMusic`, `SetCastleFlagPos`; `SetStartLeader` interpretazione.
