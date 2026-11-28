# Mappa del mondo (ADR-077) e isola di Atlantide (ADR-078)

Generano `data/mappa_mondo/`. Python 3 con numpy, scipy, pillow, shapely, numba.

Ingressi (cartella `geo`, non nel progetto): Natural Earth 10m da raw.githubusercontent.com/nvkelso/natural-earth-vector
(`ne_10m_land`, `ne_10m_lakes`, `ne_10m_rivers_lake_centerlines` in geojson), rilievo `elev_bump_4k.jpg` e colori
`2_no_clouds_4k.jpg` da raw.githubusercontent.com/turban/webgl-earth/master/images; `EARLY_XL.TXT` e la LukMap decodificata
(`tools/decode_lbm.py` -> `index.npy`) dall'installazione.

Ordine (cartella di lavoro `out`):

1. `maschere.py geo out` - terra, laghi, fiumi a piena risoluzione (Malta e Rodi ingrandite).
2. `fase1_regioni.py regioni_mondo.txt EARLY_XL.TXT geo out` - crescita delle regioni dai semi a mezza risoluzione.
3. `fase2_europa.py regioni_mondo.txt EARLY_XL.TXT index.npy out 2` - l'Europa dalla LukMap deformata sulla geografia reale.
4. `fase3_finale.py regioni_mondo.txt EARLY_XL.TXT out` - bitmap a 16 bit, isole, confinanti, castelli, porti, origini.
5. `genera_startpos.py regioni_mondo.txt EARLY_XL.TXT out/finale/mondo.json out/finale` - righe dello startpos e nomi.
6. `atlantide_dati.py out` - isola di Atlantide (variante della bitmap, startpos_atlantide.txt).
7. `dipingi.py geo out 1`, poi `alberi.py geo out` (plancia), `dipingi.py geo out 1 atlantide` e
   `alberi.py geo out plancia_auror_base.jpg plancia_auror.jpg` (plancia con l'isola).
8. `confini_mondo.py out/finale/regioni.npy confini.bin` (e `regioni_auror.npy` -> `confini_auror.bin`).
   Dal 23/11/2026 accetta anche `regioni.png` come ingresso e non usa piu' shapely (levigatura: interni 4 px, coste 1,5 px,
   Chaikin x3).
8b. `regioni_vista.py regioni.png confini.bin regioni_vista.png` (e `regioni_auror.png confini_auror.bin
   regioni_vista_auror.png`): bitmap con i confini interni allineati alle linee levigate, letta solo dallo shader della
   mappa (fasce dei proprietari, provincia scelta). Va rifatta ogni volta che cambiano la bitmap o i confini.
9. `etichette.py out` - punto del nome di ogni regione di terra (`label` in `mondo.json`, usato da NameLayer); poi
   `mondo.json` va ridotto alle chiavi id, index, sea, origin, label, pixels, auror prima di copiarlo in `data/mappa_mondo/`.

Le regioni (nomi, semi, attributi, guarnigioni) stanno in `regioni_mondo.txt`; la forma dell'isola in `atlantide.py`
(`SCALE` = 1,3: l'isola e' stata ingrandita del 30% in lineare il 16/11/2026; cambiandolo vanno rifatti i passi 6-9).
`anteprima.py` disegna un ritaglio delle etichette con i nomi per il controllo a vista.

## Regioni fuori Europa ridisegnate (28/11/2026, ADR-158)

Senza rifare le fasi 1-5: `ridisegna_terre.py` riparte dalla bitmap finale di `data/mappa_mondo` e rifa' solo i pixel
delle regioni TERRA (Europa, mari uniti e Atlantide restano identici), con confini naturali (pendenza, fiumi principali
di Natural Earth come argini, rumore frattale e domain warping che si spegne vicino ai fiumi).

1. `nuove_regioni.py`: le 100 regioni nuove (da quale regione nascono, nomi, capitale, semi, attributi), i semi nuovi di
   quelle che cedono territorio, i nomi cambiati e le regioni date alle fazioni (estensione nel 1000).
2. `aggiorna_definizioni.py regioni_mondo.txt` - scrive tutto questo in regioni_mondo.txt.
3. `ridisegna_terre.py regioni_mondo.txt <data/mappa_mondo> geo out` (geo: `ne_10m_rivers_lake_centerlines.geojson`,
   `elev_bump_4k.jpg`; scrive regioni*.png/.npy, mondo.json, startpos_mondo.txt, nomi_terra.cfg, anteprima.jpg).
4. passi 8 e 8b sopra (confini_mondo.py, regioni_vista.py) per le due varianti; `anteprima_nomi.py` per il controllo.
5. nel progetto: SetRegionOwner in fazioni_mondo.txt, nomi in data/province.cfg, liste di regioni (religione_dharma,
   mercenari, unita_mondo, nomi_personaggi), poi `posiziona_luoghi.py`.
6. Con `EUROPA=1` (ADR-159) `ridisegna_terre.py` rifa' anche le province europee: semi di regioni_mondo.txt, capitale e polo
   della forma di prima, velocita' corrette perche' ogni provincia tenga la sua estensione; i confinanti dell'originale
   restano tutti (con le zone di mare di mari_uniti.cfg). Va lanciato sui dati gia' aggiornati di data/mappa_mondo.
7. Dopo ogni rigenerazione: `etichette_mari.py out/regioni.npy out/mondo.json` (punto del nome di ogni zona di mare, ADR-160).
