extends Node2D
## Mappa navigabile della campagna.
##
## Mostra MapTex.tga dell'installazione con uno shader che, partendo dalla
## mappa delle regioni (LukMap.Lbm), tinge le province col colore del
## proprietario, disegna i confini e evidenzia la provincia selezionata.
## Le coordinate del mondo sono i pixel della bitmap (2048x1536); le coordinate
## dello startpos sono 16 volte più grandi.
##
## Sopra la mappa gira una partita a turni con scontri (fasi 2 e 3): all'avvio nasce una
## partita nuova (GameSetup.new_game) per la fazione di campaign_settings.gd; la tinta dei
## proprietari segue lo stato (StateTint). L'interfaccia legge lo stato e invia solo comandi
## (GameCommands, TurnProcessor, SaveGame): nessuna regola di gioco sta qui (ADR-003, ADR-008).
##
## La plancia è disegnata piatta in una vista intermedia (SubViewport "World") e proiettata
## sullo schermo in prospettiva, come vista da una camera inclinata (MapProjection e
## src/map/perspective_view.gdshader); mouse e segnalini passano dalla stessa proiezione.
##
## Comandi: rotella = zoom sul cursore; trascinare col tasto sinistro o centrale o frecce =
## sposta la mappa (WASD non più: D apre la diplomazia); P = prospettiva sì/no; Pagina su/giù = più o meno inclinata;
## clic sinistro (senza trascinare) = seleziona la provincia o il segnalino di un esercito/flotta/agente;
## clic destro con un esercito del giocatore selezionato = ordina il movimento verso la regione
## confinante, o l'attacco se è ostile (freccia rossa; sulla regione dell'esercito = annulla il
## movimento); Invio = fine anno;
## clic destro con un agente del giocatore selezionato (fase 5a): su una regione senza missioni possibili =
## movimento (via mare come gli eserciti; sulla regione dell'agente = annulla gli ordini); su una regione di un'altra
## fazione, su un segnalino di esercito o sulla regione dell'agente = menu con le missioni valide (alleanza, tregua,
## matrimonio, corruzione, nozze con un generale, assassinio, processo dell'inquisitore) con probabilità e prezzo;
## clic destro con un esercito crociato del giocatore (fase 5c, segnato da croce o mezzaluna) che non ha ancora un
## bersaglio: su una regione = ne sceglie il bersaglio (GameCommands.set_crusade_target; l'esercito riceve il percorso
## per terra); con il bersaglio già scelto il clic destro è il movimento di sempre; il pulsante «Scegli il bersaglio»
## del pannello dell'esercito apre l'elenco dei bersagli validi (nome, proprietario, motivo) e «Togli il bersaglio»;
## in alto compaiono «Scomunicati dal …» (tooltip con gli effetti) e l'avviso del Papa; crociate e jihad si reclutano
## dall'elenco delle unità della provincia ([Crociata], [Jihad]);
## selezione multipla (2026-11-10, CampaignUiGroup): Alt+clic sulle pedine proprie le aggiunge o le toglie, Alt+trascinamento
## su un punto vuoto disegna un riquadro che le prende; trascinandone una (anche senza Alt) o col clic destro vanno tutte
## sull'obiettivo (movimento, attacco, unione su un esercito proprio); un clic normale o Esc toglie la selezione;
## F5 = salvataggio rapido; F9 = caricamento rapido; Esc = chiude il menu/pannello o deseleziona;
## F1 = riepilogo della campagna; C = corte (capo, eredi, generali); D = diplomazia (relazioni con le fazioni);
## B = alterna i confini vettoriali (BorderExtractor, nitidi a ogni zoom) e quelli disegnati dallo shader;
## R (fase 5b) = alterna la tinta dei proprietari e quella della religione maggioritaria di ogni provincia (con legenda);
## G (fase 6b) = classifica delle fazioni per province, reddito e quota (pulsante «Classifica»); in alto «Province 12/48» è
## l'avanzamento verso il dominio (province controllate / necessarie, tooltip con la soglia). Un evento storico (fase 6a) apre una
## finestra con titolo e testo originali di Events.txt e una riga con l'effetto (Chiudi, Esc o Invio per il prossimo); disastri,
## Orda d'Oro e storia stanno nella sezione «Eventi e storia» del resoconto. Vittoria per dominio, sconfitta e fine della campagna
## aprono la schermata di fine partita (classifica; «Continua a giocare» dopo il dominio): a partita finita Fine anno e Invio
## sono disattivati (Invio riapre la schermata).

const MainScene := preload("res://scenes/main.gd")
const Settings := preload("res://scenes/campaign_settings.gd")
const ArmyLayerScript := preload("res://scenes/army_layer.gd")
const SHADER_PATH := "res://src/map/campaign_map.gdshader"
const VIEW_SHADER_PATH := "res://src/map/perspective_view.gdshader"
const MAP_TEXTURE := "Textures/campmap/MapTex.tga"

## Origine dell'immagine della mappa mostrata (originale o HD), per il riepilogo a schermo.
var _map_source := ""
const MAX_ZOOM := 8.0
const WORLD_START_ZOOM := 0.75   ## ADR-077: zoom d'apertura sulla mappa del mondo
const ZOOM_STEP := 1.15
const KEY_PAN_SPEED := 900.0       ## pixel dello schermo al secondo
const MENU_SCENE := "res://scenes/main_menu.tscn"
const TOP_OVERSCROLL := 125.0     ## pixel dello schermo oltre il bordo nord della mappa: la barra in alto e una pedina
const BOTTOM_OVERSCROLL := 40.0   ## oltre il bordo sud: la riga di stato
const DRAG_THRESHOLD := 6.0
const DRAG_TARGET_MOVE := Color(0.55, 0.85, 0.4)     ## provincia d'arrivo: movimento
const DRAG_TARGET_ATTACK := Color(0.9, 0.22, 0.15)   ## attacco
const DRAG_TARGET_FAR := Color(0.62, 0.6, 0.56)      ## fuori portata quest'anno (flotta: rotta di piu' anni; agente: si avvia)
const DRAG_TARGET_AGENT := Color(0.45, 0.7, 0.95)    ## missione di un agente        ## pixel oltre i quali il tasto sinistro trascina invece di cliccare
const TILT_STEP := 0.1             ## variazione dell'inclinazione con Pagina su/giù
const PANEL_WIDTH := 540.0          ## pergamena della provincia (richiesta di Federico del 2026-11-15: piu' larga, era 420)
const TOP_BAR_HEIGHT := 48.0       ## spazio sotto la barra in alto occupato dai pannelli
const TOAST_SECONDS := 4.0
const SECTION_COLOR := UiTheme.INK_TITLE
const EVENTS_WIDTH := 700.0             ## larghezza del testo del resoconto di fine anno
const EVENTS_MIN_HEIGHT := 120.0        ## altezza minima dell'area di scorrimento del resoconto
const EVENTS_MAX_HEIGHT := 0.62         ## altezza massima, in proporzione alla finestra
const BAD_COLOR := UiTheme.INK_BAD
const OWNER_RELIGION_COLOR := UiTheme.INK_GOOD        ## religione del proprietario nel pannello della provincia
const CARD_SIZE := Vector2(56, 56)                     ## carta di un'unita' nel pannello dell'esercito (originale 50x50)
## Icone rifatte (edifici 272x200, carte 200x200): dal 2026-11-15 (richiesta di Federico) si mostrano grandi, a meta' della
## loro misura, nella finestra della provincia e nella pergamena.
const BUILT_ICON_SIZE := Vector2(88, 65)               ## tessera di un edificio costruito nel pannello (originale 68x50)
const MODAL_ICON_SIZE := Vector2(136, 100)             ## tessera nella finestra di costruzione
const MODAL_CARD_SIZE := Vector2(100, 100)             ## carta nella finestra di arruolamento
const MODAL_TILE_WIDTH := 150.0                        ## larghezza minima di una tessera della finestra della provincia
const MODAL_SIZE := Vector2(1110, 600)                 ## area delle schede della finestra della provincia (era 760x520)
## La pergamena dell'esercito non si mostra piu' (richiesta di Federico dell'11/11/2026, ADR-035): i suoi comandi stanno
## nella barra in basso (`_refresh_army_actions`). Con `true` torna, per confronto.
const ARMY_PANEL := false
const PENNANT_SIZE := Vector2(25, 55)                  ## pennacchio del comandante sulla carta (originale 14x31)
## Scheda di unita' ed edifici (2026-11-15): vetrina con l'icona rifatta ingrandita, dati a destra.
const INFO_SHOWCASE := Vector2(330, 300)               ## vetrina dell'immagine
const INFO_PICTURE := 280.0                            ## lato massimo dell'immagine nella vetrina
const INFO_GROUND := 34.0                              ## altezza del «terreno» (ombra) dal fondo della vetrina
const INFO_RIGHT_WIDTH := 500.0                        ## colonna dei dati
const INFO_BODY_HEIGHT := 480.0                        ## altezza fissa del corpo della scheda (la colonna dei dati scorre)
const INFO_LABEL_WIDTH := 110.0                        ## etichette delle righe (Richiede, Epoche...)
const INFO_UNLOCK_CARD := Vector2(64, 64)              ## carte delle unita' sbloccate da un edificio
const HELP_COLUMN_WIDTH := 520.0   ## colonne della finestra «Comandi e tasti» (CampaignUiHelp)
const HELP_SECTION_COLUMNS := [0, 0, 1, 0, 0, 1]   ## colonna di ogni sezione: mappa, selezione, agenti, province a sinistra; eserciti e partita a destra
const HELP_TEXT_SIZE := 15
const COURT_TEXT_WIDTH := 720.0    ## larghezza del testo di un personaggio nel pannello della corte (allargata il 20/11/2026)
const SEAL_IMAGE := "campmap/Menu/seal.BIF"   ## sigillo di ceralacca del fine anno (40x41, 2 fotogrammi)
const SEAL_SIZE := 46.0
const END_YEAR_TOOLTIP := "Esegue il fine anno: movimenti, battaglie, assedi, reddito, costruzioni e reclutamento."
const CHOOSER_PLACEHOLDER := -1    ## metadato della prima voce dei selettori (nessuna scelta)

var _data: CampaignData
var _region_map: RegionMap
var _table_image: Image
var _table_texture: ImageTexture
var _reach_texture: ImageTexture   ## regioni raggiungibili dalla pedina trascinata (256x1, R = CampaignUiMoves.REACH_* x 50)
var _reach_shown := {}             ## regione -> REACH_* mostrate ora (vuoto = nessuna), per i test e il colore del bersaglio
var _map_material: ShaderMaterial
var _border_layer: BorderLayer
var _name_layer: NameLayer          ## nomi delle regioni sulla mappa del mondo (ADR-077); N li mostra o li nasconde
var _border_thread: Thread
var _vector_borders := true       ## B alterna vettoriali (true) e shader (false)
var _religion_tint := false       ## R alterna la tinta dei proprietari (false) e quella della religione maggioritaria (true)
var _legend_panel: PanelContainer ## legenda della tinta religiosa (visibile solo con la tinta religiosa)
var _borders_ready := false       ## true quando le polilinee sono state estratte o lette dalla cache
var _selected: CampaignData.Region
var _zoom := 1.0
var _min_zoom := 0.25
var _map_size := Vector2(2048, 1536)
var _ready_to_navigate := false
var _projection: MapProjection
var _view_material: ShaderMaterial
var _last_tilt := 1.0              ## inclinazione da ripristinare quando P riattiva la prospettiva
var _left_down := false            ## tasto sinistro premuto sulla mappa
var _dragging := false             ## il tasto sinistro sta trascinando la mappa (niente clic al rilascio)
var _press_pos := Vector2.ZERO
## Fase 8: pedina del giocatore presa con il tasto sinistro (esercito o agente); trascinata e lasciata su una regione vale come
## il clic destro (muovi, attacca, missione), come nell'originale. Tipo "esercito" o "agente", id 0 = nessuna.
var _drag_target_hostile := false     ## la provincia evidenziata sarebbe un attacco (suono del rilascio)
var _drag_target_group := -1      ## provincia evidenziata sotto la pedina trascinata (gruppo della regione), -1 = nessuna
var _piece_drag_kind := ""
var _hud: OriginalHud                ## barra in basso e minimappa dell'originale (src/ui/original_hud.gd)
var _details := false               ## pergamena informativa della pedina selezionata aperta (secondo clic, Dettagli)
var _province_details := false      ## pergamena della provincia aperta (clic destro sulla provincia, Dettagli)
var _commander_menu: PopupMenu       ## comandanti possibili per l'esercito scelto (pulsante «Comandante» della barra)
var _governor_menu: PopupPanel       ## scelta del governatore o di chi riceve una carica (scheda Governo, 20/11/2026)
## Luoghi leggendari (26/11/2026): pallini e medaglioni sulla mappa, scheda del luogo, finestra delle scelte.
var _site_layer: SiteLayer
var _sites_all := false                ## bussola della minimappa: medaglioni di tutti i luoghi scoperti aperti
var _site_panel: PanelContainer
var _site_box: VBoxContainer
var _site_choice_panel: PanelContainer
var _site_choice_title: Label
var _site_choice_text: Label
var _site_choice_list: VBoxContainer
var _site_choice_queue: Array[int] = []
var _site_choice_current := 0
var _character_panel: PanelContainer  ## scheda di un personaggio con il ritratto (clic destro sulla carta del comandante)
var _character_box: VBoxContainer
var _rulers_panel: PanelContainer     ## sala dei regnanti: i capi in carica di tutte le fazioni
var _rulers_grid: GridContainer
var _rulers_note: Label
var _rulers_corner: Button
var _modal_tab_row: HBoxContainer     ## schede della finestra della provincia, come quelle della pergamena
var _menu_corner: Button            ## pulsante «Menu» sempre in vista in alto a destra
var _game_menu: PanelContainer      ## menu di gioco con Esc (salva, carica, menu iniziale), come il MenuBox dell'originale
var _minimap_dirty := true
var _seen := {}                     ## regioni visibili al giocatore (nebbia di guerra), aggiornate a ogni ricostruzione delle pedine
var _menu_agent_id := 0           ## agente del menu delle missioni aperto (anche se non e' selezionato: menu da trascinamento)
var _piece_drag_id := 0
var _group: Array[int] = []         ## selezione multipla (Alt+clic, Alt+riquadro): eserciti propri mossi insieme (CampaignUiGroup)
var _alt_press := false             ## il tasto sinistro e' stato premuto con Alt
var _box_selecting := false         ## Alt + trascinamento su un punto vuoto: riquadro della selezione multipla

var _message: Label
var _info_panel: PanelContainer
var _info_box: VBoxContainer       ## contenuto del pannello della provincia
var _info_label: Label
var _province_box: VBoxContainer   ## parte del pannello ricostruita a ogni aggiornamento
var _summary_panel: PanelContainer
var _summary_button: Button
var _mode_label: Label                ## stato della mappa nel menu delle opzioni (clic sullo stemma della barra in basso)
var _economy_panel: PanelContainer   ## proventi delle province nel dettaglio (pulsante Economia, F1)
var _economy_box: VBoxContainer
var _economy_open := ""   ## provincia della finestra Economia con il dettaglio dei porti aperto ("" = nessuna)
var _map_options: PanelContainer      ## menu delle opzioni della mappa (richiesta di Federico, 2026-11-10)
var _map_borders_button: Button
var _map_tint_button: Button
var _help_label: Label
var _help_panel: PanelContainer
var _top_shield: TextureRect
var _province_shield: TextureRect
var _province_title: Label
var _army_shield: TextureRect
var _army_cards: HFlowContainer
var _army_card_columns: Array[VBoxContainer] = []   ## colonna di ogni carta (vi si aggiunge la casella della pila)

# Partita (dati statici + stato dinamico).
var _state: GameState
var _units: UnitProdLoader.UnitTable
var _buildings: BuildingProdLoader.BuildingTable
var _heroes: HeroesData = null
var _rules: Rules
var _player_id := ""               ## fazione del giocatore normalizzata (maiuscolo)
var _anchors := {}                 ## id regione -> Vector2 (castello o baricentro della zona di mare)
var _castle_widen := {}   ## regione -> fattore d'ingombro del castello (fortezza degli Auror, ADR-076)
var _selected_army := 0            ## id dell'esercito selezionato, 0 = nessuno
var _selected_agent := 0           ## id dell'agente selezionato (fase 5a), 0 = nessuno
var _fold := {}                    ## sezioni del pannello provincia: chiave -> true se chiusa
var _province_tab_box: HBoxContainer   ## riga delle schede, subito sotto il titolo della pergamena
var _province_tab := 0             ## scheda aperta della pergamena della provincia (PROVINCE_TABS), resta la stessa cambiando provincia

# Barra in alto, avvisi, pannelli.
var _top_bar: PanelContainer
var _year_label: Label
var _treasury_label: Label
var _income_label: Label
var _end_year_button: BaseButton   ## sigillo di ceralacca dell'originale (campmap/Menu/seal.BIF), o pulsante di testo
var _toast: Label
## Riquadro del messaggio in alto: cornice dei pannelli e delle finestre, angoli stondati (richiesta di Federico del
## 2026-11-13: la scritta sulla mappa senza fondo era poco leggibile).
var _toast_box: PanelContainer
var _toast_holder: CenterContainer   ## striscia in alto larga quanto la finestra: tiene il riquadro centrato a ogni misura
var _hover_panel: PanelContainer      ## riquadro al passaggio del mouse sulla mappa (CampaignUiHover, richiesta del 2026-11-13)
var _hover_label: RichTextLabel       ## BBCode: nemici in rosso, neutrali in blu, alleati in verde
var _hover_text := ""
var _motion_all := 0                  ## movimenti del mouse visti da _input (anche sopra l'interfaccia)
var _motion_map := 0                  ## ultimo di quei movimenti arrivato alla mappa: se resta indietro il puntatore e' sull'interfaccia
var _toast_serial := 0
var _army_layer: ArmyLayerScript
var _army_panel: PanelContainer
var _army_label: Label
var _army_cancel_button: Button
var _army_assault_button: Button
var _army_castle_button: Button
var _selected_castle := ""          ## castello scelto col clic (id della regione): il pannello di rassegna mostra la guarnigione
var _card_pick: Array[int] = []       ## carte (indici delle pile) dell'esercito scelto, scelte per separarle trascinandole
var _card_pick_army := 0              ## esercito a cui si riferisce _card_pick
var _card_drag_army := 0              ## esercito da cui si stanno trascinando carte (0 = nessun trascinamento)
var _card_drag_icon: Panel
var _review_cards: Array = []       ## carte del pannello di rassegna del castello: {"esercito", "pila"} per il clic sulla carta
var _markers_zoom := 0.0           ## zoom dell'ultima disposizione delle pedine (si ridispongono se cambia molto)
var _review_tabs: Array = []        ## pannello di rassegna della provincia: scheda della finestra della provincia per ogni voce (-1 = nessuna)
var _queues_panel: PanelContainer   ## elenco delle code di produzione di tutte le province (tasto Q)
var _queues_box: VBoxContainer
var _queues_busy_only := false      ## nell'elenco delle code: solo le province con qualcosa in coda
var _war_label: Label
## Assalti ordinati in questa sessione, usati solo se la simulazione non espone il flag
## (id dell'esercito -> true). Si svuota a fine anno e al caricamento.
var _assault_local := {}
var _command_names := {}           ## nomi dei comandi di GameCommands (riempito alla prima chiamata)
var _events_panel: PanelContainer
var _events_tabs: TabContainer           ## «Messaggi» e «Agenti» (18/11/2026)
var _recruit_group := -1                 ## scheda dell'arruolamento: 0 truppe, 1 flotta, 2 agenti (18/11/2026)
var _agents_scroll: ScrollContainer
var _agents_list: VBoxContainer
var _events_title: Label
var _events_subtitle: Label
var _events_scroll: ScrollContainer
var _events_label: RichTextLabel
var _court_panel: PanelContainer
var _court_title: Label
var _court_box: VBoxContainer
var _court_shield: TextureRect
var _court_button: Button
var _agent_panel: PanelContainer
var _agent_sheet: PanelContainer    ## scheda dell'agente con il ritratto (Dettagli, richiesta di Federico del 2026-11-13)
var _agent_sheet_box: VBoxContainer
var _agent_label: Label
var _agent_cancel_move_button: Button
var _agent_cancel_mission_button: Button
var _agent_hint: Label
var _mission_menu: PanelContainer
var _mission_menu_box: VBoxContainer
var _mission_menu_entries: Array[Dictionary] = []
var _diplomacy_panel: PanelContainer
var _diplomacy_title: Label
var _diplomacy_box: VBoxContainer
var _diplomacy_shield: TextureRect
var _diplomacy_button: Button
var _army_commander_label: Label
var _army_attr_box: VBoxContainer   ## attributi del comandante come icone (fase 8)
var _army_commander_row: HBoxContainer
var _army_commander_select: OptionButton
var _army_target_button: Button     ## «Scegli il bersaglio» (fase 5c), solo per un esercito crociato del giocatore
var _army_stacks_box: VBoxContainer  ## pile dell'esercito del giocatore con le caselle per dividere e unire
var _army_stack_checks: Array[CheckBox] = []
var _army_split_row: HBoxContainer
var _army_retrain_row: HBoxContainer      ## «Riaddestra le pile scelte» e «Annulla riaddestramento» (sotto la riga del dividere)
var _army_retrain_button: Button
var _army_retrain_cancel_button: Button
var _army_partner_select: OptionButton
var _army_dismiss_row: HBoxContainer      ## «Congeda le unità scelte» (ADR-031), sotto il riaddestramento
var _army_dismiss_button: Button
var _dismiss_army := 0                    ## esercito e pile in attesa di conferma
var _dismiss_indices := PackedInt32Array()
var _papal_label: Label             ## «Scomunicati dal …» nella barra in alto (fase 5c)
var _warning_panel: PanelContainer  ## avviso del Papa sotto la barra (fase 5c)
var _warning_label: Label
var _progress_label: Label          ## «Province 12/48», avanzamento del dominio nella barra in alto (fase 6b)
var _standings_button: Button
var _standings_panel: PanelContainer
var _standings_title: Label
var _standings_box: VBoxContainer
const HISTORY_WIDTH_SHARE := 0.5      ## larghezza della finestra illustrata degli eventi, in proporzione alla finestra di gioco
const HISTORY_MIN_WIDTH := 640.0
const HISTORY_MAX_WIDTH := 940.0
const HISTORY_TEXT_INSET := 92.0      ## larghezza della finestra meno quella del testo (margini, piastra, barra di scorrimento)
const HISTORY_TEXT_SHARE := 0.3       ## altezza massima del testo (poi scorre), in proporzione allo spazio sopra la barra
const ALERT_PAN_SECONDS := 0.6        ## durata dello spostamento della mappa sul luogo di un avviso
const ALERT_MAX_ZOOM := 3.0           ## un avviso non ingrandisce oltre (chi era piu' vicino viene allontanato un po')
const ALERT_EUROPE_ZOOM := 2.0        ## mappa d'Europa: zoom minimo dell'avviso, in multipli dello zoom minimo
const ALERT_WORLD_ZOOM := 1.0         ## mappa del mondo: zoom minimo dell'avviso
var _history_panel: IllustratedModal  ## finestra illustrata degli eventi: storici, avvisi (CampaignUiAlerts), notizie
var _history_text: Label
var _history_scroll: ScrollContainer
var _history_effect: Label
var _history_button: Button
var _history_skip: Button
var _alert_marker: AlertMarker = null  ## segnale pulsante sul luogo dell'avviso aperto
var _alert_place := ""                 ## luogo dell'avviso aperto ("" = nessuno)
var _alert_return := {}                ## camera e zoom prima del primo avviso dell'anno: {"pos", "zoom"}
var _alert_tween: Tween = null
var _report_pending := {}              ## resoconto dell'anno da aprire dopo le finestre: {"anno", "sezioni", "fine"}
var _history_queue: Array[Dictionary] = []   ## finestre ancora da mostrare, nell'ordine del registro
var _prisoner_panel: PanelContainer  ## finestra dei prigionieri (ADR-073): libera, riscatto, giustizia; paga o rifiuta
var _prisoner_title: Label
var _prisoner_text: Label
var _prisoner_buttons: Array[Button] = []
var _prisoner_queue: Array[int] = []
var _prisoner_current := 0
var _prisoner_choices: Array[String] = []
var _proposal_panel: PanelContainer  ## finestra delle proposte ricevute dall'IA (fase 7b)
var _proposal_title: Label
var _proposal_text: Label
var _proposal_accept: Button
var _proposal_refuse: Button
var _proposal_later: Button
var _proposal_queue: Array[int] = []   ## id delle proposte ancora da mostrare
var _proposal_current := 0             ## id della proposta mostrata (0 = nessuna)
var _proposals_button: Button          ## barra in alto: «Proposte (N)», riapre la coda
const END_PICTURE_SIZE := Vector2(600, 450)  ## immagine di fine partita (640x480 dell'originale)
var _province_modal: PanelContainer   ## finestra della provincia (fase 8d): schede Costruzione e Arruolamento
var _province_modal_title: Label
var _province_tabs: TabContainer
var _modal_build_box: VBoxContainer
var _modal_recruit_box: VBoxContainer
var _modal_merc_box: VBoxContainer
var _saves_panel: SaveLoadPanel     ## salvataggi con nome (fase 8c)
var _confirm_veil: ColorRect          ## velo scuro dietro la finestra di conferma (ferma i clic sulla mappa)
var _confirm_panel: PanelContainer    ## finestra di conferma con la cornice dei pannelli (menu iniziale, congedo)
var _confirm_title: Label
var _confirm_text: Label
var _confirm_ok: Button
var _confirm_cancel: Button
var _confirm_action := Callable()
var _unit_info_panel: PanelContainer   ## scheda dell'unita' (fase 8b): clic destro su una carta
var _unit_info_picture: TextureRect
var _unit_info_showcase: Control
var _unit_info_name: Label
var _unit_info_type: Label
var _unit_info_leader: Label
var _unit_info_text: Label
var _unit_info_sections: VBoxContainer
var _unit_info_scroll: ScrollContainer
var _unit_info_costs: GridContainer
var _unit_info_prev: Button
var _unit_info_next: Button
var _unit_info_demolish: Button   ## 15/11: «Demolisci» nella scheda di un edificio costruito (manuale p37, pulsante Distruggi)
var _unit_info_building: Array = []   ## [famiglia, livello] dell'edificio in vista, per ◀ ▶
var _end_panel: PanelContainer      ## schermata di fine partita (fase 6b)
var _end_title: Label
var _end_picture_box: Control
var _end_picture: TextureRect
var _end_ribbon_title: Label
var _end_text: Label
var _end_box: VBoxContainer
var _end_continue_button: Button
var _end_close_button: Button
var _end_pending := false           ## la schermata di fine partita aspetta che le finestre storiche siano chiuse

@onready var _world: SubViewport = $World
@onready var _sprite: Sprite2D = $World/Map
@onready var _camera: Camera2D = $World/Camera
@onready var _view_rect: ColorRect = $Backdrop/View
@onready var _ui: CanvasLayer = $Ui


func _ready() -> void:
	# ADR-077: minimappa nelle proporzioni della mappa del mondo (prima di costruire la barra)
	OriginalHud.set_minimap_aspect(WorldMap.ASPECT if WorldMap.available() else 0.0)
	_setup_view()
	_build_ui()
	_border_layer = BorderLayer.new()
	_border_layer.name = "Borders"
	_world.add_child(_border_layer)
	_world.move_child(_border_layer, _sprite.get_index() + 1)   # subito sopra la mappa
	_name_layer = NameLayer.new()
	_name_layer.name = "Names"
	_name_layer.camera = _camera
	_world.add_child(_name_layer)
	_world.move_child(_name_layer, _border_layer.get_index() + 1)   # sopra i confini, sotto le pedine
	if not GameFiles.campaign_available():
		_show_message(Lang.t("Dati della campagna non trovati:\n%s") % GameFiles.startpos())
		return
	if not _load_map():
		return
	_ready_to_navigate = true
	GameAudio.play_music(GameAudio.map_music_key(_player_religion()))
	get_viewport().size_changed.connect(_on_viewport_resized)
	_zoom = _min_zoom
	_camera.zoom = Vector2(_zoom, _zoom)
	_border_layer.set_zoom(_zoom)
	_camera.position = _map_size / 2.0
	_start_near_capital()
	_clamp_camera()
	if not AssetLibrary.is_available():
		var problems := AssetLibrary.errors()
		var why := problems[0] if not problems.is_empty() else Lang.t("Immagini dell'interfaccia non trovate.")
		push_warning(why)
		_toast_show(why + Lang.t(" L'interfaccia usa gli stili di riserva."))


func _exit_tree() -> void:
	if _border_thread != null and _border_thread.is_started():
		_border_thread.wait_to_finish()


func _process(delta: float) -> void:
	if _border_thread != null and _border_thread.is_started() and not _border_thread.is_alive():
		_finish_border_job()
	if not _ready_to_navigate:
		return
	var direction := Vector2.ZERO
	# Solo le frecce: D apre il pannello della diplomazia (e C quello della corte).
	if Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if direction != Vector2.ZERO:
		_camera.position += direction.normalized() * KEY_PAN_SPEED * delta / _zoom
		_clamp_camera()
	if _army_layer != null:
		_army_layer.set_view(_camera.position, _zoom, _view_size(), _projection)
	if _site_layer != null:
		_site_layer.set_view(_camera.position, _zoom, _view_size(), _projection)
	if _border_layer != null:
		# confini a riquadri (BorderLayer): si aggiornano allo zoom solo quelli in vista
		var flat := _view_size() / _zoom
		_border_layer.set_view(Rect2(_camera.position - flat / 2.0, flat))
	if _hud != null and _hud.visible:
		_update_minimap_view()
	if _alert_marker != null and _alert_marker.visible and _anchors.has(_alert_place):
		_alert_marker.position = _world_to_screen(_anchors[_alert_place]).round()
	if _hover_panel != null and _hover_panel.visible and (_motion_map != _motion_all or _confirm_is_open()):
		_hide_hover()   # il puntatore e' passato sull'interfaccia (o c'e' una finestra di conferma)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_motion_all += 1
	# ADR-148 (Federico: «spesso il trascinamento di un'unita' si blocca e resta sospesa, come se perdesse il focus»): la carta
	# presa riceveva movimenti e rilascio solo finche' il suo controllo esisteva; se la barra si ridisegnava durante il
	# trascinamento il controllo spariva, il rilascio non arrivava piu' e l'icona restava a mezz'aria. Ora movimento e
	# rilascio si leggono qui, per tutta la finestra; clic destro o Esc annullano.
	if _card_drag_army != 0:
		if event is InputEventMouseMotion:
			_on_card_drag_moved(-1)
		elif event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				_on_card_drag_released(-1)
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				_cancel_card_drag()
				get_viewport().set_input_as_handled()
		elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			_cancel_card_drag()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# finestra che perde il focus (Alt+Tab, notifica) con una carta in mano: il rilascio non arriverebbe, si annulla
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_card_drag()


## Annulla il trascinamento delle carte in corso: l'icona sparisce e le pile restano dove sono.
func _cancel_card_drag() -> void:
	if _card_drag_army == 0:
		return
	_card_drag_army = 0
	if _card_drag_icon != null:
		_card_drag_icon.visible = false
	_end_piece_drag()
	_refresh_review()


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_navigate:
		return
	if event is InputEventMouseButton:
		_hide_hover()
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_zoom_at(button.position, _zoom * ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom_at(button.position, _zoom / ZOOM_STEP)
			MOUSE_BUTTON_LEFT:
				# Il clic vale al rilascio, e solo se il tasto non ha trascinato la mappa.
				if button.pressed:
					_left_down = true
					_dragging = false
					_press_pos = button.position
					_alt_press = button.alt_pressed
					_box_selecting = false
					_grab_piece(button.position)
				else:
					if _left_down and _box_selecting:
						_finish_box(button.position)
					elif _left_down and _dragging and _piece_drag_id > 0:
						_drop_piece(button.position)
					elif _left_down and not _dragging:
						if _alt_press:
							_on_alt_click(_press_pos)
						else:
							_on_left_click(_press_pos)
					_left_down = false
					_dragging = false
					_end_piece_drag()
					_clear_box_selection()
			MOUSE_BUTTON_RIGHT:
				if button.pressed:
					_on_right_click(button.position)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_motion_map = _motion_all
		if motion.button_mask == 0 and not _left_down:
			_update_hover(motion.position)
		else:
			_hide_hover()
		# Il tasto destro serve per gli ordini: la mappa si trascina col sinistro o col centrale.
		if _left_down and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_left_down = false   # rilascio avvenuto sopra l'interfaccia
			_dragging = false
			_end_piece_drag()
			_clear_box_selection()
		if _left_down and _piece_drag_id > 0:
			# si trascina una pedina: la mappa resta ferma e la pedina segue il puntatore (con i segnalini disegnati, una linea)
			if not _dragging and motion.position.distance_to(_press_pos) > DRAG_THRESHOLD:
				_dragging = true
				GameAudio.play_sfx("prendi")
				_show_reach()
				if not _army_layer.begin_drag(_piece_drag_kind, _piece_drag_id, _press_pos):
					_army_layer.set_drag_line(_press_pos, motion.position)
				elif _is_group_drag():
					_army_layer.set_drag_followers(_group)
			if _dragging:
				if _army_layer.is_dragging_piece():
					_army_layer.move_drag(motion.position)
				else:
					_army_layer.set_drag_line(_press_pos, motion.position)
				_update_drag_target(motion.position)
		elif _left_down and _alt_press:
			# Alt + trascinamento su un punto vuoto: riquadro della selezione multipla (la mappa resta ferma)
			if not _box_selecting and motion.position.distance_to(_press_pos) > DRAG_THRESHOLD:
				_box_selecting = true
				_dragging = true
			if _box_selecting:
				_army_layer.set_box(_press_pos, motion.position)
		elif _left_down:
			if _dragging:
				_pan_screen(motion.position - motion.relative, motion.position)
			elif motion.position.distance_to(_press_pos) > DRAG_THRESHOLD:
				_dragging = true
				_pan_screen(_press_pos, motion.position)
		elif (motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
			_pan_screen(motion.position - motion.relative, motion.position)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if _confirm_is_open():
				# finestra di conferma aperta: Esc rinuncia, gli altri tasti non fanno nulla (niente fine anno per sbaglio)
				if key.keycode == KEY_ESCAPE:
					_confirm_close()
				get_viewport().set_input_as_handled()
				return
			if key.keycode == KEY_ESCAPE:
				if _history_panel.visible:
					_on_history_close()
				elif _prisoner_panel.visible:
					pass   # sui prigionieri si decide con i pulsanti (ADR-073)
				elif _proposal_panel.visible:
					_on_proposal_later()
				elif _site_panel != null and _site_panel.visible:
					_site_panel.visible = false
				elif _character_panel != null and _character_panel.visible:
					_character_panel.visible = false
				elif _rulers_panel != null and _rulers_panel.visible:
					_rulers_panel.visible = false
				elif _end_panel.visible:
					_on_end_close()
				elif _unit_info_panel.visible and _province_modal.visible:
					_unit_info_panel.visible = false
				elif _economy_panel != null and _economy_panel.visible:
					_economy_panel.visible = false
				elif _map_options.visible:
					_map_options.visible = false
				elif _queues_panel != null and _queues_panel.visible:
					_queues_panel.visible = false
				elif _province_modal.visible:
					_province_modal.visible = false
				elif _saves_panel.visible:
					_saves_panel.close()
				elif _unit_info_panel.visible:
					_unit_info_panel.visible = false
				elif _mission_menu.visible:
					_hide_mission_menu()
				elif _standings_panel.visible:
					_standings_panel.visible = false
				elif _diplomacy_panel.visible:
					_diplomacy_panel.visible = false
				elif _court_panel.visible:
					_court_panel.visible = false
				elif _events_panel.visible:
					_hide_events()
				elif _game_menu != null and _game_menu.visible:
					_game_menu.visible = false
				elif _agent_sheet != null and _agent_sheet.visible:
					_details = false   # chiude la scheda, l'agente resta selezionato
					_agent_sheet.visible = false
					_refresh_review()
				elif _army_panel.visible or _agent_panel.visible:
					_close_piece_panel()
				elif _info_panel.visible:
					_province_details = false
					_refresh_province_panel()
				elif _selected_army != 0 or _selected_agent != 0 or _selected != null or not _group.is_empty():
					_group.clear()
					_selected_army = 0
					_selected_agent = 0
					_select(null)
					_rebuild_markers()
					_refresh_army_panel()
					_refresh_agent_panel()
				elif _game_menu != null:
					_game_menu.visible = true
				else:
					_selected_army = 0
					_selected_agent = 0
					_select(null)
					_rebuild_markers()
					_refresh_army_panel()
					_refresh_agent_panel()
			elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
				if _history_panel.visible:
					_on_history_close()
				elif _prisoner_panel.visible or _proposal_panel.visible:
					pass   # prigionieri e proposte si decidono con i pulsanti
				else:
					_on_end_year()
			elif key.keycode == KEY_F5:
				_quick_save()
			elif key.keycode == KEY_F9:
				_quick_load()
			elif key.keycode == KEY_F1:
				_toggle_economy()
			elif key.keycode == KEY_C:
				_toggle_court()
			elif key.keycode == KEY_H:
				_help_panel.visible = not _help_panel.visible
			elif key.keycode == KEY_D:
				_toggle_diplomacy()
			elif key.keycode == KEY_G:
				_toggle_standings()
			elif key.keycode == KEY_K:
				_toggle_rulers()
			elif key.keycode == KEY_B:
				_vector_borders = not _vector_borders
				_update_border_mode()
			elif key.keycode == KEY_R:
				_toggle_religion_tint()
			elif key.keycode == KEY_P:
				if _projection.is_flat():
					_set_tilt(maxf(_last_tilt, MapProjection.MIN_TILT + TILT_STEP))
				else:
					_last_tilt = _projection.tilt
					_set_tilt(MapProjection.MIN_TILT)
			elif key.keycode == KEY_COMMA:
				_cycle_province(-1, key.shift_pressed)
			elif key.keycode == KEY_PERIOD:
				_cycle_province(1, key.shift_pressed)
			elif key.keycode == KEY_N and _name_layer != null:
				_name_layer.set_shown(not _name_layer.shown)
			elif key.keycode == KEY_Q:
				_toggle_queues_panel()
			elif key.keycode == KEY_PAGEUP:
				_set_tilt(_projection.tilt + TILT_STEP)
			elif key.keycode == KEY_PAGEDOWN:
				_set_tilt(_projection.tilt - TILT_STEP)


# --- Caricamento ---------------------------------------------------------------

## Immagine della mappa: la versione ingrandita (Upscayl) se presente nella cartella HD,
## altrimenti MapTex.tga originale. Restituisce null e mostra un messaggio se non legge nulla.
func _load_map_image() -> Image:
	var hd_path := GameFiles.hd_image(MAP_TEXTURE)
	if hd_path != "":
		var hd := Image.load_from_file(hd_path)
		if hd != null and not hd.is_empty():
			_map_source = "HD %dx%d" % [hd.get_width(), hd.get_height()]
			return hd
		push_warning("Immagine HD non leggibile, uso l'originale: %s" % hd_path)
	var tga_path := GameFiles.path(MAP_TEXTURE)
	if not FileAccess.file_exists(tga_path):
		_show_message(Lang.t("Immagine della mappa non trovata:\n%s") % tga_path)
		return null
	var image := Image.new()
	var err := image.load_tga_from_buffer(FileAccess.get_file_as_bytes(tga_path))
	if err != OK:
		_show_message(Lang.t("Impossibile leggere %s (errore %d).") % [tga_path, err])
		return null
	_map_source = Lang.t("originale %dx%d") % [image.get_width(), image.get_height()]
	return image


## Plancia dipinta della mappa del mondo (ADR-077), con l'isola di Atlantide in modalita' Auror (ADR-078).
func _load_world_image() -> Image:
	var image := WorldMap.load_texture_image(Scenario.auror)
	if image == null:
		_show_message(Lang.t("Immagine della mappa non trovata:\n%s") % WorldMap.texture_path(Scenario.auror))
		return null
	_map_source = Lang.t("mondo %dx%d") % [image.get_width(), image.get_height()]
	return image


func _load_map() -> bool:
	if GameLaunch.load_save != "":
		# ADR-068: il salvataggio dice se la partita e' storica o con gli Auror; i dati si leggono per quello scenario
		var saved := SaveGame.summary(GameLaunch.load_save)
		if not saved.is_empty():
			Scenario.set_from_id(str(saved.get("scenario", Scenario.AUROR)))
	_data = Scenario.load_startpos()   # ADR-068: storico (Danesi, Norvegesi, Svedesi) o modalita' Auror
	FactionStyle.apply_overrides(_data)   # fase 8: colori della tabella (gli Auror bianchi e neri, i Danesi bianchi e rossi)
	AssetLibrary.use_campaign(_data)
	# ADR-077: mappa del mondo (data/mappa_mondo) se c'e', con l'isola di Atlantide in modalita' Auror (ADR-078)
	var world := WorldMap.available()
	var lbm: LbmReader = WorldMap.load_map(Scenario.auror) if world else LbmReader.load_file(GameFiles.lookup_map())
	if not lbm.is_valid():
		_show_message(Lang.t("Impossibile leggere la mappa delle regioni:\n%s") % lbm.error)
		return false
	var image := _load_world_image() if world else _load_map_image()
	if image == null:
		return false
	image.generate_mipmaps()
	_region_map = RegionMap.new(lbm, _data)
	_map_size = Vector2(lbm.width, lbm.height)
	# La texture può avere una risoluzione diversa dalla bitmap: la scala riporta tutto ai pixel della bitmap.
	_sprite.texture = ImageTexture.create_from_image(image)
	_sprite.scale = Vector2(lbm.width / float(image.get_width()), lbm.height / float(image.get_height()))
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	_table_image = _region_map.build_table(null)
	_table_texture = ImageTexture.create_from_image(_table_image)
	var map_material := ShaderMaterial.new()
	map_material.shader = load(SHADER_PATH) as Shader
	# sulla mappa del mondo lo shader legge la bitmap con i confini levigati (solo grafica, 23/11/2026)
	var index_image: Image = (lbm as WorldMap).view_image() if lbm is WorldMap else lbm.to_image()
	map_material.set_shader_parameter("index_tex", ImageTexture.create_from_image(index_image))
	map_material.set_shader_parameter("table_tex", _table_texture)
	map_material.set_shader_parameter("index_groups", world)
	_sprite.material = map_material
	_map_material = map_material
	_summary_button.visible = true
	_update_min_zoom()
	if not _start_game():
		return false
	_compute_anchors(lbm)
	if lbm is WorldMap:
		_name_layer.set_regions(_data, lbm as WorldMap)   # la plancia del mondo non ha i nomi dipinti
	_top_bar.visible = false   # l'originale non ha barra in alto: tesoreria, anno e pulsanti stanno nella barra in basso
	_hud.visible = true
	_layout_hud()
	_refresh_all()
	_start_border_job(lbm)
	return true


# --- Confini vettoriali ----------------------------------------------------------

## Finché le polilinee non sono pronte restano i confini dello shader; l'estrazione
## (o la lettura della cache) gira in un thread per non bloccare la finestra.
func _start_border_job(lbm: LbmReader) -> void:
	_update_border_mode()
	_border_thread = Thread.new()
	if lbm is WorldMap:
		# ADR-077: confini precalcolati da tools/mondo/confini_mondo.py
		_border_thread.start(_world_border_job.bind(WorldMap.borders_path((lbm as WorldMap).auror_variant)))
		return
	_border_thread.start(_border_job.bind(GameFiles.lookup_map(), lbm.indices, lbm.width, lbm.height))


func _world_border_job(path: String) -> Dictionary:
	var start := Time.get_ticks_msec()
	var borders := BorderExtractor.load_world(path)
	return {"borders": borders, "from_cache": true, "ms": Time.get_ticks_msec() - start}


func _border_job(path: String, indices: PackedByteArray, w: int, h: int) -> Dictionary:
	var extractor := BorderExtractor.new()
	var borders := extractor.load_or_extract(path, indices, w, h)
	return {"borders": borders, "from_cache": extractor.from_cache, "ms": extractor.elapsed_ms}


func _finish_border_job() -> void:
	var result: Dictionary = _border_thread.wait_to_finish()
	_border_thread = null
	var list: Array[BorderExtractor.Border] = []
	list.assign(result["borders"])
	_border_layer.set_borders(list)
	_border_layer.set_zoom(_zoom)
	_borders_ready = not list.is_empty()
	print("Confini vettoriali: %d polilinee in %d ms (%s)" % [list.size(), result["ms"], "cache" if result["from_cache"] else "estratti"])
	_update_border_mode()


func _update_border_mode() -> void:
	var use_vector := _vector_borders and _borders_ready
	if _map_material != null:
		_map_material.set_shader_parameter("draw_borders", not use_vector)
	_border_layer.visible = use_vector
	if _mode_label == null:
		return
	var borders := Lang.t("shader (estrazione dei vettoriali in corso)") if _vector_borders and not _borders_ready else (Lang.t("vettoriali") if use_vector else Lang.t("shader"))
	var lines := PackedStringArray([Lang.t("Confini: %s") % borders, Lang.t("Tinta: %s") % (Lang.t("religione") if _religion_tint else Lang.t("proprietari"))])
	if _projection != null:
		lines.append(Lang.t("Prospettiva: %s") % (Lang.t("piatta") if _projection.is_flat() else Lang.t("inclinata")))
	if _map_source != "":
		lines.append(Lang.t("Mappa: %s") % _map_source)
	_mode_label.text = "\n".join(lines)
	if _map_borders_button != null:
		_map_borders_button.text = Lang.t("Passa ai confini %s (B)") % (Lang.t("dello shader") if _vector_borders else Lang.t("vettoriali"))
		_map_tint_button.text = Lang.t("Passa alla tinta %s (R)") % (Lang.t("dei proprietari") if _religion_tint else Lang.t("della religione"))


## Menu delle opzioni della mappa (richiesta di Federico, 2026-11-10: la scritta in basso a sinistra spostata qui): si apre
## con un clic sullo stemma della fazione nella barra in basso. Stato di confini, tinta, prospettiva e immagine della mappa,
## con i pulsanti che fanno quello che fanno i tasti B, R e P.
func _build_map_options() -> void:
	_map_options = PanelContainer.new()
	_map_options.visible = false
	_map_options.z_index = 4
	_map_options.anchor_left = 0.5
	_map_options.anchor_right = 0.5
	_map_options.anchor_top = 1.0
	_map_options.anchor_bottom = 1.0
	_map_options.offset_left = -400.0
	_map_options.offset_right = -120.0
	_map_options.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(_map_options)
	var margin := _margin()
	_map_options.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = Lang.t("Opzioni della mappa")
	title.theme_type_variation = "Subtitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _make_button(Lang.t("Chiudi"))
	close.pressed.connect(func() -> void: _map_options.visible = false)
	head.add_child(close)
	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_mode_label)
	box.add_child(UiTheme.divider())
	_map_borders_button = _make_button(Lang.t("Confini (B)"))
	_map_borders_button.pressed.connect(func() -> void:
		_vector_borders = not _vector_borders
		_update_border_mode())
	box.add_child(_map_borders_button)
	_map_tint_button = _make_button(Lang.t("Tinta (R)"))
	_map_tint_button.pressed.connect(_toggle_religion_tint)
	box.add_child(_map_tint_button)
	var tilt := _make_button(Lang.t("Prospettiva piatta o inclinata (P)"))
	tilt.pressed.connect(func() -> void:
		if _projection.is_flat():
			_set_tilt(maxf(_last_tilt, MapProjection.MIN_TILT + TILT_STEP))
		else:
			_last_tilt = _projection.tilt
			_set_tilt(MapProjection.MIN_TILT)
		_update_border_mode())
	box.add_child(tilt)
	var help := _make_button(Lang.t("Comandi e tasti (H)"))
	help.pressed.connect(func() -> void: _help_panel.visible = not _help_panel.visible)
	box.add_child(help)


func _toggle_map_options() -> void:
	_map_options.visible = not _map_options.visible
	if _map_options.visible:
		GameAudio.play_sfx("pergamena")
		_update_border_mode()


# --- Camera --------------------------------------------------------------------

## Prepara la proiezione e lo shader che porta la vista piatta (SubViewport) sullo schermo.
func _setup_view() -> void:
	var tilt := UserSettings.tilt()
	_projection = MapProjection.new(get_viewport_rect().size, tilt)
	_last_tilt = _projection.tilt if not _projection.is_flat() else Settings.PERSPECTIVE_TILT
	_view_material = ShaderMaterial.new()
	_view_material.shader = load(VIEW_SHADER_PATH) as Shader
	_view_material.set_shader_parameter("world_tex", _world.get_texture())
	_view_rect.material = _view_material
	_apply_projection()


## Adatta la vista piatta allo schermo e all'inclinazione correnti.
func _apply_projection() -> void:
	_projection.screen_size = get_viewport_rect().size
	var flat := _projection.flat_size()
	var render_k := _projection.render_scale()
	_world.size = Vector2i(maxi(1, ceili(flat.x * render_k)), maxi(1, ceili(flat.y * render_k)))
	if render_k < 1.0:
		_world.size_2d_override = Vector2i(ceili(flat.x), ceili(flat.y))
		_world.size_2d_override_stretch = true
	else:
		_world.size_2d_override = Vector2i.ZERO
		_world.size_2d_override_stretch = false
	_view_material.set_shader_parameter("tilt", _projection.tilt)


## Cambia l'inclinazione tenendo fermo il punto della mappa al centro dello schermo.
func _set_tilt(new_tilt: float) -> void:
	var k := clampf(new_tilt, MapProjection.MIN_TILT, MapProjection.MAX_TILT)
	if is_equal_approx(k, _projection.tilt):
		return
	var center_screen := get_viewport_rect().size / 2.0
	var anchor := _screen_to_world(center_screen)
	_projection.tilt = k
	_apply_projection()
	_update_min_zoom()
	_zoom = clampf(_zoom, _min_zoom, MAX_ZOOM)
	_camera.zoom = Vector2(_zoom, _zoom)
	_border_layer.set_zoom(_zoom)
	_camera.position = anchor - (_projection.screen_to_flat(center_screen) - _view_size() / 2.0) / _zoom
	_clamp_camera()
	_toast_show(Lang.t("Vista dall'alto.") if _projection.is_flat() else Lang.t("Prospettiva: inclinazione %.1f.") % _projection.tilt)


## Mappa del mondo (ADR-077): si parte vicino alla propria capitale, con uno zoom simile a quello della mappa d'Europa,
## invece che dal planisfero intero.
func _start_near_capital() -> void:
	if not RegionMap.world or _state == null:
		return
	var home := ""
	var f := _data.faction(_player_id) if _data != null else null
	if f != null:
		home = f.leader_region
	var p := _state.province(home) if home != "" else null
	if p == null or p.owner != _player_id:
		home = ""
		for q in _state.provinces:
			if q.owner == _player_id:
				home = q.id
				break
	if not _anchors.has(home):
		return
	_zoom = clampf(WORLD_START_ZOOM, _min_zoom, MAX_ZOOM)
	_camera.zoom = Vector2(_zoom, _zoom)
	_border_layer.set_zoom(_zoom)
	_camera.position = _anchors[home]
	_rebuild_markers()


## Dimensione della vista piatta (in cui lavora la Camera2D).
func _view_size() -> Vector2:
	return _projection.flat_size()


func _screen_to_world(screen: Vector2) -> Vector2:
	return _camera.position + (_projection.screen_to_flat(screen) - _view_size() / 2.0) / _zoom


## Sposta la mappa in modo che il punto sotto `from` finisca sotto `to` (trascinamento).
func _pan_screen(from: Vector2, to: Vector2) -> void:
	_camera.position += _screen_to_world(from) - _screen_to_world(to)
	_clamp_camera()


## Zoom minimo: la mappa intera entra nella striscia più stretta (in basso) e in altezza.
func _update_min_zoom() -> void:
	var view := _view_size()
	_min_zoom = minf(_projection.bottom_width() / _map_size.x, view.y / _map_size.y)


func _zoom_at(screen: Vector2, new_zoom: float) -> void:
	var anchor := _screen_to_world(screen)
	_zoom = clampf(new_zoom, _min_zoom, MAX_ZOOM)
	_camera.zoom = Vector2(_zoom, _zoom)
	_border_layer.set_zoom(_zoom)
	# Il punto sotto il cursore deve restare fermo.
	_camera.position = anchor - (_projection.screen_to_flat(screen) - _view_size() / 2.0) / _zoom
	_clamp_camera()
	# le pedine si dispongono in coordinate della mappa dentro le loro regioni: con uno zoom molto diverso si ridispongono
	if _markers_zoom > 0.0 and absf(log(_zoom / _markers_zoom)) > 0.22:
		_rebuild_markers()


## Tiene la vista dentro la mappa; se la mappa è più piccola della vista la centra.
## In orizzontale conta la striscia in basso (la più stretta): in prospettiva ai lati in alto
## può comparire il tavolo, ma ogni angolo della mappa resta raggiungibile.
func _clamp_camera() -> void:
	var half := Vector2(_projection.bottom_width(), _view_size().y) / (2.0 * _zoom)
	var pos := _camera.position
	if half.x * 2.0 >= _map_size.x:
		pos.x = _map_size.x / 2.0
	else:
		pos.x = clampf(pos.x, half.x, _map_size.x - half.x)
	# in alto la barra copre la mappa e le pedine delle regioni piu' a nord (Norvegia, Finlandia) salgono oltre il bordo:
	# la vista puo' andare un po' oltre, quanto la barra piu' una pedina; in basso quanto la riga di stato
	var top_margin := (_projection.screen_to_flat(Vector2(0.0, TOP_OVERSCROLL)).y - _projection.screen_to_flat(Vector2.ZERO).y) / _zoom
	var bottom_margin := (_projection.screen_to_flat(Vector2(0.0, get_viewport_rect().size.y)).y
		- _projection.screen_to_flat(Vector2(0.0, get_viewport_rect().size.y - BOTTOM_OVERSCROLL)).y) / _zoom
	if half.y * 2.0 >= _map_size.y + top_margin + bottom_margin:
		pos.y = (_map_size.y + bottom_margin - top_margin) / 2.0
	else:
		pos.y = clampf(pos.y, half.y - top_margin, _map_size.y - half.y + bottom_margin)
	_camera.position = pos


func _on_viewport_resized() -> void:
	_layout_hud()
	_apply_projection()
	_update_min_zoom()
	_zoom = clampf(_zoom, _min_zoom, MAX_ZOOM)
	_camera.zoom = Vector2(_zoom, _zoom)
	_border_layer.set_zoom(_zoom)
	_clamp_camera()
	_on_viewport_resized_alerts()


# --- Partita -------------------------------------------------------------------

## Carica le tabelle prod e crea la partita nuova per la fazione del giocatore.
func _start_game() -> bool:
	var unit_path := GameFiles.prod_file(_data.unit_prod_file)
	var building_path := GameFiles.prod_file(_data.building_prod_file)
	if not FileAccess.file_exists(unit_path) or not FileAccess.file_exists(building_path):
		_show_message(Lang.t("File prod non trovati:\n%s\n%s") % [unit_path, building_path])
		return false
	_units = Scenario.load_units(unit_path)
	_buildings = Scenario.load_buildings(building_path)
	_rules = Rules.load_file()
	Scenario.apply_rules(_rules)   # ADR-068: nello scenario storico nessuno ha i poteri degli Auror
	for problem in _rules.errors:
		push_warning(problem)
	_player_id = SimUtil.norm(GameLaunch.faction if GameLaunch.faction != "" else Settings.PLAYER_FACTION)
	# Nomi, re ed eroi famosi dal file indicato dallo startpos (SetNameData), altrimenti quello della XL.
	var names_file := _data.name_data_basename()
	if names_file == "":
		names_file = HeroesLoader.DEFAULT_FILE
	_heroes = Scenario.load_heroes(GameFiles.heroes_file(names_file))
	if GameLaunch.load_save != "":
		# fase 8c: partita scelta dal menu (Continua o Carica); la fazione del giocatore e' quella salvata
		var r := SaveGame.load_file(GameLaunch.load_save, _data, _units, _buildings, _rules, _heroes)
		if not bool(r["ok"]):
			_show_message(Lang.t("Caricamento non riuscito: %s") % str(r["errore"]))
			return false
		_state = r["stato"]
		_player_id = _saved_player(_state, _player_id)
		_proposal_queue = CampaignUiProposals.queue_ids(_state, _player_id)
		_prisoner_queue = CampaignUiPrisoners.queue_ids(_state, _player_id)
		_site_choice_queue = CampaignUiSites.queue_ids(_state, _player_id)
		return _mark_player()
	var seed_number := GameLaunch.seed_value if GameLaunch.seed_value != 0 else Settings.NEW_GAME_SEED
	_state = GameSetup.new_game(_data, _units, _buildings, _rules, seed_number, _heroes)
	_state.scenario = Scenario.id()
	if not _mark_player():
		return false
	if not _state.setup_errors.is_empty():
		push_warning("Partita nuova: %d anomalie nei dati iniziali (la prima: %s)" % [_state.setup_errors.size(), _state.setup_errors[0]])
	return true


## Fazione del giocatore di uno stato caricato (quella segnata nel salvataggio), `fallback` se nessuna lo e'.
static func _saved_player(state: GameState, fallback: String) -> String:
	for f in state.factions:
		if f.is_player:
			return f.id
	return fallback


func _player_religion() -> String:
	var f := _data.faction(_player_id) if _data != null else null
	return f.religion if f != null else ""


func _is_islamic_player() -> bool:
	return GameAudio.map_music_key(_player_religion()) == "mappa_islamica"


## Difficolta' dell'IA: quella scelta nel menu, poi le impostazioni dell'utente.
func _difficulty() -> String:
	return GameLaunch.difficulty if GameLaunch.difficulty != "" else UserSettings.difficulty()


## Segna la fazione del giocatore nello stato; falso (con messaggio) se non esiste.
func _mark_player() -> bool:
	if _state.faction(_player_id) == null:
		_show_message(Lang.t("Fazione del giocatore sconosciuta: %s\nControlla scenes/campaign_settings.gd.") % _player_id)
		return false
	for f in _state.factions:
		f.is_player = (f.id == _player_id)
	return true


## Punto di ogni regione dove stanno i segnalini: il castello (SetCastle / 16) per la terra,
## il pixel della zona più vicino al baricentro per il mare (e per le terre senza castello).
## Calcolato una volta sola.
func _compute_anchors(lbm: LbmReader) -> void:
	_anchors.clear()
	if lbm is WorldMap:
		# ADR-077: zone di mare ancorate al punto interno precalcolato (anche quelle a cavallo del bordo del Pacifico)
		var wm := lbm as WorldMap
		for r in _data.regions:
			if (r.is_sea or r.castle_pos == Vector2i.ZERO) and wm.anchors.has(r.id):
				_anchors[r.id] = wm.anchors[r.id]
			elif not r.is_sea:
				_anchors[r.id] = Vector2(r.castle_pos) / float(RegionMap.STARTPOS_SCALE)
		return
	var group_of := PackedInt32Array()
	group_of.resize(RegionMap.TABLE_SIZE)
	for i in range(RegionMap.TABLE_SIZE):
		group_of[i] = RegionMap.group_for_index(i)
	var wanted := {}
	for r in _data.regions:
		if r.is_sea or r.castle_pos == Vector2i.ZERO:
			wanted[RegionMap.group_for_index(_region_map.indices_for_region(r)[0])] = true
	var zones := MarkerLayout.zone_anchors(lbm.indices, lbm.width, lbm.height, group_of, wanted, 2)
	for r in _data.regions:
		if r.is_sea or r.castle_pos == Vector2i.ZERO:
			var group := RegionMap.group_for_index(_region_map.indices_for_region(r)[0])
			if zones.has(group):
				var zone_point: Vector2 = zones[group]
				_anchors[r.id] = zone_point
		else:
			_anchors[r.id] = Vector2(r.castle_pos) / float(RegionMap.STARTPOS_SCALE)


## Aggiorna tutto ciò che dipende dallo stato di gioco.
func _refresh_all() -> void:
	_minimap_dirty = true
	_apply_tint()
	_rebuild_markers()
	_refresh_top_bar()
	_refresh_province_panel()
	_refresh_army_panel()
	_refresh_agent_panel()
	_refresh_court_panel()
	_refresh_diplomacy_panel()
	_refresh_standings_panel()
	_refresh_proposals_button()


## Tabella dei colori: evidenziazione dalla selezione, proprietari dallo stato.
func _apply_tint() -> void:
	var base := _region_map.build_table(_selected)
	if _religion_tint:
		_table_image = StateTint.apply_religion(base, _region_map, _state)
	else:
		_table_image = StateTint.apply(base, _region_map, _state)
	_table_texture.update(_table_image)
	if _map_material != null:
		# stile dell'originale con la tinta dei proprietari; la religione resta a riempimento (con la legenda)
		_map_material.set_shader_parameter("original_style", not _religion_tint)


## R: alterna la tinta dei proprietari e quella della religione maggioritaria (legenda a sinistra).
func _toggle_religion_tint() -> void:
	if _state == null or not _ready_to_navigate:
		return
	_religion_tint = not _religion_tint
	if _legend_panel != null:
		_legend_panel.visible = _religion_tint
	_apply_tint()
	_update_border_mode()
	_toast_show(Lang.t("Tinta: religione maggioritaria (R per tornare ai proprietari).") if _religion_tint else Lang.t("Tinta: proprietari."))


func _refresh_top_bar() -> void:
	var f := _state.faction(_player_id)
	if f == null:
		return
	_year_label.text = Lang.t("%s · Anno %d · %s") % [FactionStyle.full_name_of(_player_id), _state.year, CampaignUiText.era_name(_state.era)]
	_top_shield.texture = AssetLibrary.faction_shield(_player_id)
	_treasury_label.text = Lang.t("Tesoro: %d") % f.treasury
	if f.treasury < 0:
		_treasury_label.add_theme_color_override("font_color", BAD_COLOR)
	else:
		_treasury_label.remove_theme_color_override("font_color")
	var net_text := "-"
	if not f.last_income.is_empty():
		net_text = CampaignUiText.signed(int(f.last_income.get("netto", 0)))
	var balance := CampaignUiText.balance_lines(f)
	_income_label.text = balance[0] if not balance.is_empty() else Lang.t("Reddito netto dell'ultimo anno: %s") % net_text
	_income_label.tooltip_text = "\n".join(balance)
	var enemies := CampaignUiText.enemies_of(_state, _player_id)
	_war_label.text = CampaignUiText.war_bar_text(enemies)
	_war_label.tooltip_text = CampaignUiText.war_tooltip(enemies)
	if enemies.is_empty():
		_war_label.remove_theme_color_override("font_color")
	else:
		_war_label.add_theme_color_override("font_color", BAD_COLOR)
	var excommunication := CampaignUiPapacy.excommunication_info(_state, _player_id)
	_papal_label.visible = bool(excommunication["scomunicata"])
	_papal_label.text = str(excommunication["testo"])
	_papal_label.tooltip_text = str(excommunication["tooltip"])
	var papal_warning := CampaignUiPapacy.warning_info(_state, _player_id)
	_warning_panel.visible = bool(papal_warning["visibile"])
	_warning_label.text = str(papal_warning["testo"])
	_warning_label.tooltip_text = str(papal_warning["tooltip"])
	var progress := CampaignUiVictory.progress_info(_state, _player_id)
	_progress_label.text = str(progress["testo"])
	_progress_label.tooltip_text = str(progress["tooltip"])
	if bool(progress["raggiunto"]):
		_progress_label.add_theme_color_override("font_color", OWNER_RELIGION_COLOR)
	else:
		_progress_label.remove_theme_color_override("font_color")
	var over := _state.is_game_over()
	_end_year_button.disabled = over
	_end_year_button.tooltip_text = CampaignUiVictory.game_over_hint(_state) if over else Lang.t(END_YEAR_TOOLTIP)
	if _hud != null:
		var money_tip := PackedStringArray([_income_label.tooltip_text if _income_label.tooltip_text != "" else _income_label.text,
			_war_label.tooltip_text if _war_label.tooltip_text != "" else _war_label.text])
		if _papal_label.visible:
			money_tip.append(_papal_label.text)
		var year_tip := "%s\n%s" % [_year_label.text, str(progress["tooltip"]) if str(progress["tooltip"]) != "" else str(progress["testo"])]
		_hud.set_status(f.treasury, _state.year, "\n".join(money_tip), year_tip, over, _end_year_button.tooltip_text)
		_hud.set_shield(AssetLibrary.faction_shield(_player_id))


## Riquadro al passaggio del mouse (richiesta di Federico, 2026-11-13, come nell'originale): sulla pedina chi e' e se e'
## vostra, nemica, alleata o neutrale; su una zona di mare lo stato delle acque (libere, vostre, nemiche, blocco navale); su
## una provincia di chi e'. I testi vengono da CampaignUiHover.
func _update_hover(screen: Vector2) -> void:
	if _state == null or _confirm_is_open():
		_hide_hover()
		return
	var text := ""
	# luoghi leggendari: il pallino sotto il puntatore si apre nel medaglione con il riquadro
	var site_id := _site_layer.site_at(screen) if _site_layer != null else ""
	if _site_layer != null:
		_site_layer.set_hovered(site_id)
	var agent := _state.agent(_army_layer.agent_at(screen)) if site_id == "" else null
	var site := _state.rules.sites.site(site_id) if site_id != "" else null
	if site != null:
		text = CampaignUiSites.hover_text(_state, site)
	elif agent != null:
		text = CampaignUiHover.agent_text(_state, _player_id, agent, true)
	else:
		var army := _state.army(_army_layer.army_at(screen))
		if army != null:
			text = CampaignUiHover.army_text(_state, _player_id, army, true)
		else:
			var world := _screen_to_world(screen)
			var region := _region_map.region_at_pixel(floori(world.x), floori(world.y))
			var castle_region := _army_layer.castle_at(screen)
			if castle_region != "":
				region = _state.campaign.region(castle_region)
			if region != null:
				text = CampaignUiHover.region_text(_state, _player_id, region.id, _seen, true)
	if text == "":
		_hide_hover()
		return
	if _hover_panel == null:
		_hover_panel = PanelContainer.new()
		_hover_panel.theme_type_variation = "TooltipPanel"
		_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hover_panel.z_index = 20
		_hover_label = RichTextLabel.new()
		_hover_label.bbcode_enabled = true
		_hover_label.fit_content = true
		_hover_label.scroll_active = false
		_hover_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_hover_label.add_theme_color_override("default_color", UiTheme.INK)
		_hover_label.add_theme_font_size_override("normal_font_size", 14)
		_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hover_panel.add_child(_hover_label)
		_ui.add_child(_hover_panel)
	if text != _hover_text:
		_hover_text = text
		_hover_label.text = text
		_hover_panel.reset_size()
	var view := get_viewport().get_visible_rect().size
	var box := _hover_panel.get_combined_minimum_size()
	var pos := screen + (Vector2(30, -box.y - 6.0) if site != null else Vector2(18, 22))   # luoghi: sopra a destra, lascia libero il nome sotto il medaglione
	if pos.y < 4.0:
		pos.y = screen.y + 30.0
	if pos.x + box.x > view.x - 4.0:
		pos.x = screen.x - box.x - 12.0
	if pos.y + box.y > view.y - 4.0:
		pos.y = screen.y - box.y - 12.0
	_hover_panel.position = pos.round()
	_hover_panel.visible = true


func _hide_hover() -> void:
	if _hover_panel != null:
		_hover_panel.visible = false
	if _site_layer != null:
		_site_layer.set_hovered("")


func _toast_show(text: String) -> void:
	_toast.text = CampaignUiText.humanize_ids(_state, text) if _state != null else text   # mai id grezzi (27/11/2026)
	# i messaggi lunghi vanno a capo entro il 60% della finestra (al massimo 760 punti), quelli brevi restano su una riga
	_toast.autowrap_mode = TextServer.AUTOWRAP_OFF
	_toast.custom_minimum_size = Vector2.ZERO
	var limit := minf(760.0, get_viewport().get_visible_rect().size.x * 0.6)
	if _toast.get_minimum_size().x > limit:
		_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_toast.custom_minimum_size = Vector2(limit, 0)
	_toast_box.visible = true
	_toast_serial += 1
	get_tree().create_timer(TOAST_SECONDS).timeout.connect(_on_toast_timeout.bind(_toast_serial))


func _on_toast_timeout(serial: int) -> void:
	if serial == _toast_serial:
		_toast_box.visible = false


# --- Fine anno, salvataggi ------------------------------------------------------

func _on_end_year() -> void:
	if _state == null or not _ready_to_navigate:
		return
	if _state.is_game_over():
		# partita finita (o vittoria in attesa della scelta): niente fine anno, si riapre la schermata
		_toast_show(CampaignUiVictory.game_over_hint(_state))
		_refresh_top_bar()
		if not _end_panel.visible:
			_show_end_screen()
		return
	if not CampaignUiPrisoners.queue_ids(_state, _player_id).is_empty():
		# ADR-073: prima si decide dei prigionieri (come nell'originale, la finestra non si salta)
		if not _prisoner_panel.visible:
			_prisoner_queue = CampaignUiPrisoners.queue_ids(_state, _player_id)
			_site_choice_queue = CampaignUiSites.queue_ids(_state, _player_id)
			_show_next_prisoners()
		_toast_show(Lang.t("Decidi prima la sorte dei prigionieri."))
		return
	var played_year := _state.year
	_hide_mission_menu()
	_assault_local.clear()
	GameAudio.play_sfx("fine_anno_islam" if _is_islamic_player() else "fine_anno")
	var result := CampaignTurn.advance(_state, _difficulty())   # fase 7: prima l'IA delle altre fazioni, poi il fine anno
	if not bool(result["ok"]):
		_toast_show(CampaignUiVictory.game_over_hint(_state))
		_refresh_top_bar()
		return
	var sections := CampaignUiText.year_report_sections(_state, _player_id, result)
	_refresh_all()
	var finished := CampaignUiVictory.finished_line(_state)
	# finestre illustrate una dopo l'altra (avvisi degli eventi importanti con la mappa sul luogo, eventi storici, notizie),
	# poi prigionieri, scelte dei luoghi leggendari e proposte, e solo quando sono tutte chiuse il resoconto dell'anno e la
	# schermata di fine partita (richieste di Federico del 2026-11-20 e del 2026-11-27: «la schermata di recap si apra solo
	# quando le altre sono chiuse»)
	_history_queue = CampaignUiAlerts.windows(_state, _player_id, played_year)
	_history_queue.append_array(CampaignUiEvents.historical_windows(_state))
	_history_queue.append_array(CampaignUiEvents.news_windows(_state, _player_id))
	_report_pending = {}
	if sections.is_empty() and finished == "":
		_toast_show(Lang.t("Anno %d concluso: nessun evento.") % played_year)
	else:
		_report_pending = {"anno": played_year, "sezioni": sections, "fine": finished}
	_proposal_queue = CampaignUiProposals.queue_ids(_state, _player_id)
	_prisoner_queue = CampaignUiPrisoners.queue_ids(_state, _player_id)
	_site_choice_queue = CampaignUiSites.queue_ids(_state, _player_id)
	_end_pending = CampaignUiVictory.has_end_screen(_state)
	_show_next_popup()


## Finestra del resoconto di fine anno, impaginato da CampaignUiReport; `finished` = riga di fine campagna ("" = nessuna).
func _show_events(played_year: int, sections: Array[Dictionary], finished: String = "") -> void:
	_court_panel.visible = false
	_diplomacy_panel.visible = false
	_standings_panel.visible = false
	_hide_mission_menu()
	_events_title.text = Lang.t("Anno %d concluso") % played_year
	_events_subtitle.text = CampaignUiReport.subtitle(_state.year, sections)
	_events_label.text = CampaignUiReport.bbcode(_state, sections, _player_id, finished)
	_events_tabs.current_tab = 0
	_events_panel.visible = true
	_fit_events_panel()


## L'area di scorrimento prende l'altezza del testo, fino al 62% della finestra e senza scendere sulla barra in basso; poi la
## finestra si centra nello spazio sopra la barra.
func _fit_events_panel() -> void:
	await get_tree().process_frame
	if not _events_panel.visible:
		return
	var view := get_viewport().get_visible_rect().size
	var free := view.y - (_hud.bar_height() if _hud != null else 0.0)   # spazio sopra la barra in basso
	var limit := minf(view.y * EVENTS_MAX_HEIGHT, free - 250.0)
	var wanted := _events_label.get_content_height() + 6.0
	if _events_tabs != null and _events_tabs.current_tab == 1:
		wanted = _agents_list.get_combined_minimum_size().y + 6.0   # scheda «Agenti»
	_events_scroll.custom_minimum_size.y = clampf(wanted, EVENTS_MIN_HEIGHT, maxf(limit, EVENTS_MIN_HEIGHT))
	_agents_scroll.custom_minimum_size.y = _events_scroll.custom_minimum_size.y
	_events_panel.reset_size()
	_events_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	var panel_size := _events_panel.size
	_events_panel.position = Vector2(roundf((view.x - panel_size.x) * 0.5), roundf(maxf(12.0, (free - panel_size.y) * 0.5)))


func _on_save_button() -> void:
	if _state == null or not _ready_to_navigate:
		return
	_saves_panel.open_save("%s_%d" % [FactionStyle.name_of(_player_id), _state.year])


## Torna al menu iniziale chiedendo conferma: la partita non salvata si perde.
func _on_menu_button() -> void:
	_confirm_ask(Lang.t("Menu iniziale"), Lang.t("Tornare al menu iniziale?\nLa partita non salvata andrà persa."), Lang.t("Torna al menu"), Lang.t("Resta"), func() -> void:
		GameLaunch.reset()
		get_tree().change_scene_to_file(MENU_SCENE))


## Finestra di conferma nella veste del gioco: titolo, testo e due pulsanti; `action` parte solo con la conferma. Esc o il
## pulsante di rinuncia la chiudono senza fare nulla.
func _confirm_ask(title: String, text: String, ok_text: String, cancel_text: String, action: Callable) -> void:
	if _confirm_panel == null:
		_confirm_veil = ColorRect.new()
		_confirm_veil.color = Color(0, 0, 0, 0.45)
		_confirm_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_confirm_veil.mouse_filter = Control.MOUSE_FILTER_STOP
		_confirm_veil.z_index = 30
		_ui.add_child(_confirm_veil)
		# un CenterContainer tiene la finestra al centro e alla sua misura minima anche quando il testo va a capo
		# (con i soli ancoraggi al centro la finestra nasceva troppo alta e fuori centro)
		var holder := CenterContainer.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.z_index = 31
		_ui.add_child(holder)
		_confirm_panel = PanelContainer.new()
		holder.add_child(_confirm_panel)
		_stack_sheet(_confirm_veil, _confirm_panel, 30)
		_stack_sheet(holder, _confirm_panel, 31)
		var margin := _margin()
		_confirm_panel.add_child(margin)
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(380, 0)
		box.add_theme_constant_override("separation", 10)
		margin.add_child(box)
		_confirm_title = Label.new()
		_confirm_title.theme_type_variation = "Title"
		_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_confirm_title)
		box.add_child(UiTheme.divider())
		_confirm_text = Label.new()
		_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_confirm_text.custom_minimum_size = Vector2(380, 0)
		_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_confirm_text)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 16)
		box.add_child(row)
		_confirm_cancel = _make_button(Lang.t("Annulla"))
		_confirm_cancel.pressed.connect(_confirm_close)
		row.add_child(_confirm_cancel)
		_confirm_ok = _make_button(Lang.t("Conferma"))
		_confirm_ok.pressed.connect(_on_confirm_ok)
		row.add_child(_confirm_ok)
	_confirm_title.text = title
	_confirm_text.text = text
	_confirm_ok.text = ok_text
	_confirm_cancel.text = cancel_text
	_confirm_action = action
	_confirm_veil.visible = true
	_confirm_panel.visible = true


func _confirm_is_open() -> bool:
	return _confirm_panel != null and _confirm_panel.visible


func _confirm_close() -> void:
	if _confirm_panel != null:
		_confirm_panel.visible = false
		_confirm_veil.visible = false
	_confirm_action = Callable()


func _on_confirm_ok() -> void:
	var action := _confirm_action
	_confirm_close()
	if action.is_valid():
		action.call()


func _quick_save() -> void:
	if _state == null or not _ready_to_navigate:
		return
	var r := SaveGame.save_file(_state, Settings.QUICK_SAVE)
	if bool(r["ok"]):
		_toast_show(Lang.t("Partita salvata (%s).") % Settings.QUICK_SAVE)
	else:
		_toast_show(Lang.t("Salvataggio non riuscito: %s") % str(r["errore"]))


func _quick_load() -> void:
	_load_named(Settings.QUICK_SAVE)


## Salvataggio con nome (fase 8c), dalla finestra dei salvataggi.
func _save_named(save_name: String) -> void:
	if _state == null or not _ready_to_navigate:
		return
	var r := SaveGame.save_file(_state, save_name)
	_saves_panel.close()
	if bool(r["ok"]):
		GameAudio.play_sfx("salvato")
		_toast_show(Lang.t("Partita salvata (%s).") % save_name)
	else:
		_toast_show(Lang.t("Salvataggio non riuscito: %s") % str(r["errore"]))


func _on_load_chosen(save_name: String) -> void:
	_saves_panel.close()
	_load_named(save_name)


func _load_named(save_name: String) -> void:
	if _state == null or not _ready_to_navigate:
		return
	var saved := SaveGame.summary(save_name)
	if not saved.is_empty() and str(saved.get("scenario", Scenario.AUROR)) != Scenario.id():
		# ADR-068: salvataggio dell'altro scenario (storico o Auror): servono i suoi dati, si ricarica la mappa
		GameLaunch.load_game(save_name)
		get_tree().reload_current_scene()
		return
	var r := SaveGame.load_file(save_name, _data, _units, _buildings, _rules, _heroes)
	if not bool(r["ok"]):
		_toast_show(Lang.t("Caricamento non riuscito: %s") % str(r["errore"]))
		return
	var loaded: GameState = r["stato"]
	_state = loaded
	_player_id = _saved_player(_state, _player_id)
	if not _mark_player():
		return
	_events_panel.visible = false
	_history_panel.visible = false
	_history_queue.clear()
	_report_pending = {}
	_alert_return = {}
	_end_alerts()
	_proposal_panel.visible = false
	_proposal_current = 0
	_proposal_queue = CampaignUiProposals.queue_ids(_state, _player_id)
	_prisoner_panel.visible = false
	_prisoner_current = 0
	_prisoner_queue = CampaignUiPrisoners.queue_ids(_state, _player_id)
	_site_choice_queue = CampaignUiSites.queue_ids(_state, _player_id)
	_end_panel.visible = false
	_end_pending = false
	_hide_mission_menu()
	_assault_local.clear()
	_refresh_all()
	_toast_show(Lang.t("Partita caricata (%s): anno %d.") % [save_name, _state.year])
	if CampaignUiVictory.has_end_screen(_state):
		_show_end_screen()
	else:
		_show_next_proposal()


# --- Segnalini di eserciti e flotte ---------------------------------------------

## Da pixel dello schermo a dimensione base (slot delle pedine) a coordinate della mappa, allo zoom attuale: le pedine
## crescono con lo zoom entro i limiti di ArmyLayer.piece_scale.
func _piece_world_factor() -> float:
	var scale := clampf(ArmyLayerScript.PIECE_WORLD_HEIGHT * _zoom / ArmyLayerScript.BASE_HEIGHT, ArmyLayerScript.PIECE_MIN_SCALE, ArmyLayerScript.PIECE_MAX_SCALE)
	return scale / maxf(_zoom, 0.0001)


## Come _piece_world_factor per castelli e porti, che crescono fino a ArmyLayer.STRUCTURE_MAX_SCALE.
func _structure_world_factor() -> float:
	return ArmyLayerScript.structure_scale_at(_zoom) / maxf(_zoom, 0.0001)


## Punti della mappa dove possono stare le pedine nella regione `region_id` (richiesta di Federico, 2026-11-10: niente pedine
## in mare): disegnate in `slots` (pixel a dimensione base, intorno all'ancora), poi spostate dentro i confini e fuori dal
## castello con MarkerLayout.fit_positions.
func _fit_slots(region_id: String, anchor: Vector2, slots: PackedVector2Array, has_castle: bool) -> PackedVector2Array:
	var f := _piece_world_factor()
	var offsets := PackedVector2Array()
	for slot in slots:
		offsets.append(slot * f)
	var half := ArmyLayerScript.PIECE_HALF_WIDTH * f * 0.6
	var inside := func(p: Vector2) -> bool:
		for dx in [0.0, -half, half]:
			var r := _region_map.region_at_pixel(floori(p.x + dx), floori(p.y))
			if r == null or r.id != region_id:
				return false
		return true
	var avoid := Rect2()
	if has_castle:
		var k := _castle_factor(region_id)
		var h := ArmyLayerScript.CASTLE_HEIGHT * _structure_world_factor() * k
		var w := h * 0.95 + ArmyLayerScript.PIECE_HALF_WIDTH * f * 2.0
		avoid = Rect2(anchor.x - w * 0.5, anchor.y - h * 0.9, w, h + ArmyLayerScript.PIECE_HEIGHT * f * 0.55)
	return MarkerLayout.fit_positions(anchor, offsets, inside, ArmyLayerScript.SLOT_SPACING * f, avoid, ArmyLayerScript.SLOT_SPACING * f * 9.0)


func _rebuild_markers() -> void:
	_markers_zoom = _zoom
	_army_layer.clear_all()
	if _state.army(_selected_army) == null:
		_selected_army = 0
	_group = CampaignUiGroup.prune(_state, _player_id, _group)
	if _state.agent(_selected_agent) == null:
		_selected_agent = 0
	# nebbia di guerra (Visibility, manuale p11): le forze altrui si vedono solo nelle regioni visibili
	_seen = Visibility.visible_regions(_state, _player_id)
	_refresh_sites()
	var shown: Array[Army] = []
	for a in _state.armies:
		if not a.stacks.is_empty() and (a.faction == _player_id or _seen.has(a.region)):
			shown.append(a)
	var seen_agents: Array[AgentState] = []
	for ag in CampaignUiAgents.visible_agents(_state, _player_id):
		if ag.faction == _player_id or _seen.has(ag.region):
			seen_agents.append(ag)
	# movimento fluido (richiesta di Federico, 2026-11-10): niente frecce, le pedine proprie con un ordine stanno gia' dove
	# saranno a fine anno (CampaignUiMoves); nella simulazione restano dove sono fino al fine anno
	var groups := MarkerLayout.group_by_region(shown, CampaignUiMoves.shown_army_regions(_state, shown, _player_id))
	var agent_groups := MarkerLayout.group_agents_by_region(seen_agents, CampaignUiMoves.shown_agent_regions(seen_agents, _player_id))
	var region_keys := {}
	for key in groups:
		region_keys[key] = true
	for key in agent_groups:
		region_keys[key] = true
	var rows_by_region := {}   ## regione -> righe di segnalini (eserciti e agenti), per il simbolo di assedio
	_add_ports()
	var castled := _add_castles()   ## regioni con il castello disegnato: le pedine stanno al suo fianco
	for key in region_keys:
		var region_id: String = key
		if not _anchors.has(region_id):
			continue
		var anchor: Vector2 = _anchors[region_id]
		var ids: PackedInt32Array = groups.get(region_id, PackedInt32Array())
		var agent_ids: PackedInt32Array = agent_groups.get(region_id, PackedInt32Array())
		# con il castello: le guarnigioni davanti al castello, gli altri segnalini alla sua destra
		var has_castle := castled.has(region_id)
		var garrison_ids := PackedInt32Array()
		var field_ids := PackedInt32Array()
		var spotted_ids := PackedInt32Array()   ## pedine messe dal giocatore in un punto scelto della regione
		for army_id in ids:
			var candidate := _state.army(army_id)
			var travelling := CampaignUiMoves.army_in_transit(candidate)
			if candidate != null and not travelling and candidate.spot_here() != Vector2.INF:
				spotted_ids.append(army_id)
			elif has_castle and candidate != null and candidate.in_castle and not travelling:
				garrison_ids.append(army_id)
			else:
				field_ids.append(army_id)
		var free_agent_ids := PackedInt32Array()
		var spotted_agent_ids := PackedInt32Array()
		for agent_key in agent_ids:
			var agent_candidate := _state.agent(agent_key)
			if agent_candidate != null and not CampaignUiMoves.agent_in_transit(agent_candidate) and agent_candidate.spot_here() != Vector2.INF:
				spotted_agent_ids.append(agent_key)
			else:
				free_agent_ids.append(agent_key)
		agent_ids = free_agent_ids
		var layout := MarkerLayout.mixed_slots(field_ids.size(), agent_ids.size(), ArmyLayerScript.SLOT_SPACING)
		var army_slots: PackedVector2Array = layout["eserciti"]
		var agent_slots: PackedVector2Array = layout["agenti"]
		var side := MarkerLayout.castle_shift(layout, ArmyLayerScript.castle_side_offset(_structure_world_factor() / _piece_world_factor() * _castle_factor(region_id))) if has_castle else Vector2.ZERO
		rows_by_region[region_id] = int(layout["righe"])
		# pedine di campo e agenti dentro i confini della regione, alla destra del castello se c'e' posto
		var wanted := PackedVector2Array()
		for k in army_slots.size():
			wanted.append(army_slots[k] + side)
		for k in agent_slots.size():
			wanted.append(agent_slots[k] + side)
		var spots := _fit_slots(region_id, anchor, wanted, has_castle)
		var ordered := garrison_ids.duplicate()
		ordered.append_array(field_ids)
		for i in range(ordered.size()):
			var army := _state.army(ordered[i])
			if army == null:
				continue
			var at := anchor
			var slot := Vector2.ZERO
			if i < garrison_ids.size():
				slot = ArmyLayerScript.garrison_slot(i)
			else:
				at = spots[i - garrison_ids.size()]
			var fill := army.banner_fill(_state.rules.max_stacks)
			var piece := PieceArt.army_piece(_data, army.faction, _piece_kind(army), not army.path.is_empty(), fill)
			_army_layer.add_marker(army.id, at, slot, StateTint.owner_color(_region_map, army.faction), str(army.stack_count()), army.is_fleet, army.faction == _player_id, army.id == _selected_army or _group.has(army.id), CampaignUiPapacy.badge_of(army), piece)
			if i < garrison_ids.size():
				_army_layer.hide_marker(army.id)   # nel castello la pedina sparisce: lo stendardo del castello dice quanto e' pieno
		for army_id in spotted_ids:
			var placed := _state.army(army_id)
			var placed_fill := placed.banner_fill(_state.rules.max_stacks)
			var placed_piece := PieceArt.army_piece(_data, placed.faction, _piece_kind(placed), not placed.path.is_empty(), placed_fill)
			_army_layer.add_marker(placed.id, placed.spot_here(), Vector2.ZERO, StateTint.owner_color(_region_map, placed.faction), str(placed.stack_count()), placed.is_fleet, placed.faction == _player_id, placed.id == _selected_army or _group.has(placed.id), CampaignUiPapacy.badge_of(placed), placed_piece)
		for agent_key in spotted_agent_ids:
			var placed_agent := _state.agent(agent_key)
			var placed_agent_piece := PieceArt.agent_piece(_data, placed_agent.faction, placed_agent.type_name, not placed_agent.path.is_empty())
			_army_layer.add_agent_marker(placed_agent.id, placed_agent.spot_here(), Vector2.ZERO, StateTint.owner_color(_region_map, placed_agent.faction), CampaignUiAgents.marker_text(placed_agent), placed_agent.faction == _player_id, placed_agent.id == _selected_agent, placed_agent_piece)
		for i in range(agent_ids.size()):
			var agent_unit := _state.agent(agent_ids[i])
			if agent_unit == null:
				continue
			var agent_piece := PieceArt.agent_piece(_data, agent_unit.faction, agent_unit.type_name, not agent_unit.path.is_empty())
			_army_layer.add_agent_marker(agent_unit.id, spots[army_slots.size() + i], Vector2.ZERO, StateTint.owner_color(_region_map, agent_unit.faction), CampaignUiAgents.marker_text(agent_unit), agent_unit.faction == _player_id, agent_unit.id == _selected_agent, agent_piece)
	for region_key in CampaignUiText.sieged_regions(_state):
		if not _anchors.has(region_key) or not _seen.has(region_key):
			continue
		var rows := int(rows_by_region.get(region_key, 0))
		var siege_anchor: Vector2 = _anchors[region_key]
		_army_layer.add_siege_mark(siege_anchor, MarkerLayout.siege_symbol_offset(rows, ArmyLayerScript.SLOT_SPACING))
	# niente frecce dei movimenti ne' anelli delle province raggiungibili via mare: le pedine in viaggio sono gia' disegnate
	# all'arrivo e le regioni raggiungibili si colorano mentre si trascina una pedina (_show_reach)
	_army_layer.finish()


## Porti delle province con l'edificio PORT costruito (richiesta di Federico: come nell'originale), nel punto di SetPort con
## il molo orientato come nello startpos.
func _add_ports() -> void:
	if not AssetLibrary.is_available():
		return
	for p in _state.provinces:
		var region := _state.campaign.region(p.id)
		if region == null or not region.has_port or p.level_of(_rules.port_family) <= 0:
			continue
		var tex := PieceArt.port_piece(region.port_dir)
		if tex != null:
			_army_layer.add_port(Vector2(region.port_pos) / float(RegionMap.STARTPOS_SCALE), tex)


## Castelli delle province (richiesta di Federico: come nell'originale): immagine del grado di castello, colorata per il
## proprietario, sull'ancora della regione (SetCastle). Solo con le immagini dell'originale. Restituisce le regioni
## con il castello disegnato.
func _add_castles() -> Dictionary:
	var out := {}
	_castle_widen.clear()
	if not AssetLibrary.is_available():
		return out
	var c := _state.rules.combat
	for p in _state.provinces:
		if not _anchors.has(p.id):
			continue
		var tier := c.castle_tier(p.level_of(c.castle_family))
		if tier < 0:
			continue
		# stendardo pieno per la parte occupata della guarnigione (come le bandiere degli eserciti)
		var fill := float(Combat.garrison_load(_state, p.id)) / float(maxi(1, Combat.garrison_capacity(_state, p.id)))
		if p.owner != _player_id and not _seen.has(p.id):
			fill = 0.0   # nebbia di guerra: la guarnigione altrui fuori vista non si conosce
		var special := FortressArt.map_original(p.id)   # ADR-076: la fortezza bianca nella regione natia degli Auror
		var fortress := special != ""
		if not fortress:
			special = CastleStyle.map_original(RegionStyle.castle_faction(_state, p.id), tier)   # castelli della fazione d'origine della regione (22/11/2026)
		var tex := PieceArt.castle_piece(_data, p.owner, tier, fill, special)
		if tex == null:
			continue
		var scale := FortressArt.MAP_SCALE if fortress else 1.0
		_army_layer.add_castle(p.id, _anchors[p.id], tex, scale)
		# ingombro per le pedine: piu' alto con la scala, piu' largo se l'immagine e' piu' larga di un castello comune (~0,86)
		_castle_widen[p.id] = scale * maxf(1.0, float(tex.get_width()) / float(maxi(1, tex.get_height())) / 0.86) if fortress else 1.0
		out[p.id] = true
	return out


## Fattore dell'ingombro del castello di `region_id` rispetto a un castello comune (1 se non e' la fortezza degli Auror).
func _castle_factor(region_id: String) -> float:
	return float(_castle_widen.get(region_id, 1.0))


## Tipo di pedina dell'esercito (fase 8): flotta, crociata, jihad, con un capo o un erede al comando, oppure comune.
func _piece_kind(army: Army) -> String:
	if army.is_fleet:
		return "fleet"
	if army.is_crusade():
		return "jihad" if army.crusade_kind() == PapacyProcessor.KIND_JIHAD else "crusade"
	var special := PieceArt.special_kind(_state.units, army)   # Ankalagon: la pedina del drago
	if special != "":
		return special
	var commander := _state.commander_of(army.id)
	# solo il re ha la pedina del re; eredi e principi quella normale (richiesta di Federico, 2026-11-10)
	if commander != null and commander.role == Character.ROLE_LEADER:
		return "leader"
	return "army"


func _select_army(army_id: int) -> void:
	if army_id != 0 and army_id != _selected_army:
		GameAudio.play_sfx("seleziona")
	# come nell'originale il primo clic mostra le unita' nel pannello di rassegna, il secondo apre la pergamena
	_details = ARMY_PANEL and army_id != 0 and army_id == _selected_army
	_selected_army = army_id
	_selected_agent = 0
	if army_id != 0:
		_selected_castle = ""
	_rebuild_markers()
	_refresh_army_panel()
	_refresh_agent_panel()


## Seleziona un agente (e toglie la selezione dell'esercito): ne mostra il pannello.
func _select_agent(agent_id: int) -> void:
	_group.clear()
	_details = agent_id != 0 and agent_id == _selected_agent
	_selected_agent = agent_id
	_selected_army = 0
	if agent_id != 0:
		_selected_castle = ""
	_rebuild_markers()
	_refresh_army_panel()
	_refresh_agent_panel()


func _refresh_army_panel() -> void:
	var army := _state.army(_selected_army)
	_refresh_review()
	if army == null or not ARMY_PANEL:
		_army_panel.visible = false
		return
	# fase 8: le righe delle singole pile («  Lancieri × 100») le mostrano le carte qui sotto
	var army_lines := PackedStringArray()
	for line in CampaignUiPapacy.army_text(_state, army).split("\n"):
		if not line.begins_with("  "):
			army_lines.append(line)
	_army_label.text = "\n".join(army_lines)
	_army_shield.texture = AssetLibrary.faction_shield(army.faction)
	_refresh_army_cards(army)
	var mine := army.faction == _player_id
	var commander_lines := CampaignUiText.commander_lines(_state, army)
	var commander_text := commander_lines[0] if not commander_lines.is_empty() else ""
	_army_commander_label.text = commander_text
	_army_commander_label.visible = commander_text != ""
	# fase 8: gli attributi del comandante come icone (la seconda riga di commander_lines)
	_clear_children(_army_attr_box)
	var commander := _state.commander_of(army.id)
	if commander != null:
		_army_attr_box.add_child(_attribute_row(commander, false))
	_refresh_commander_select(army, mine)
	_army_cancel_button.visible = mine
	_army_cancel_button.disabled = army.path.is_empty() and army.pending_conflict == ""
	_refresh_assault_button(army, mine)
	_refresh_castle_button(army, mine)
	_army_target_button.visible = mine and army.is_crusade()
	if _army_target_button.visible:
		_army_target_button.tooltip_text = Lang.t("Elenco dei bersagli validi dell'%s, con proprietario e motivo. Senza bersaglio, il clic destro su una regione lo sceglie.") % CampaignUiText.army_title(army).to_lower()
	_refresh_split_controls(army, mine)
	_army_panel.visible = true


## Comandi dell'esercito scelto nella barra in basso (ADR-035): gli stessi della vecchia pergamena, i cui pulsanti (mai
## mostrati) restano la fonte di cosa si puo' fare e perche'. Solo per gli eserciti e le flotte del giocatore.
func _refresh_army_actions(army: Army) -> void:
	if army == null or army.faction != _player_id:
		return
	_refresh_assault_button(army, true)
	_refresh_castle_button(army, true)
	_refresh_split_controls(army, true)
	var list: Array = []
	if not army.path.is_empty() or army.pending_conflict != "":
		list.append({"id": "annulla_ordini", "testo": Lang.t("Annulla ordini"), "suggerimento": Lang.t("Annulla il movimento ordinato: resta dov'è."), "attivo": true})
	if _army_assault_button.visible:
		list.append({"id": "assalto", "testo": Lang.t("Annulla assalto") if _assault_ordered(army) else Lang.t("Assalta"),
			"suggerimento": "%s\n%s" % [_army_assault_button.text, _army_assault_button.tooltip_text], "attivo": not _army_assault_button.disabled})
	if _army_castle_button.visible:
		list.append({"id": "castello", "testo": Lang.pick("Esci", "Leave") if army.in_castle else Lang.t("Barricati"),
			"suggerimento": "%s\n%s" % [_army_castle_button.text, _army_castle_button.tooltip_text], "attivo": not _army_castle_button.disabled})
	if army.is_crusade():
		list.append({"id": "bersaglio", "testo": Lang.t("Bersaglio"), "suggerimento": Lang.t("Elenco dei bersagli validi, con proprietario e motivo."), "attivo": true})
	# ripristino delle forze in un clic (richiesta di Federico, 2026-11-13, ADR-046)
	var restore := CampaignUiRetrain.restore_action(_state, _player_id, army)
	if bool(restore["visibile"]):
		list.append({"id": "ripristina", "testo": str(restore["testo"]), "suggerimento": str(restore["suggerimento"]), "attivo": bool(restore["attivo"])})
	if _army_retrain_row.visible:
		var info := CampaignUiRetrain.panel_state(_state, _player_id, army, _checked_stacks())
		if bool(info["visibile"]):
			list.append({"id": "riaddestra", "testo": Lang.t("Riaddestra"), "suggerimento": Lang.t("%s\n%s\nScegli prima le carte da riportare all'organico pieno.") % [str(info["testo"]), str(info["tooltip"])], "attivo": true})
		if bool(info["annulla_visibile"]):
			list.append({"id": "annulla_riaddestramento", "testo": Lang.t("Ferma riaddestr."), "suggerimento": str(info["annulla_testo"]), "attivo": true})
	if not army.is_fleet and not CampaignUiText.eligible_commanders(_state, army).is_empty():
		list.append({"id": "comandante", "testo": Lang.t("Comandante"), "suggerimento": Lang.t("Affida l'esercito a un altro comandante."), "attivo": true})
	_hud.set_actions(list)


func _on_army_action(id: String) -> void:
	match id:
		"annulla_ordini":
			_on_cancel_move_pressed()
		"assalto":
			_on_assault_pressed()
		"castello":
			_on_castle_pressed()
		"bersaglio":
			_on_target_button_pressed()
		"riaddestra":
			_on_retrain_pressed()
		"ripristina":
			_on_restore_pressed()
		"annulla_riaddestramento":
			_on_retrain_cancel_pressed()
		"comandante":
			_open_commander_menu()


## Elenco a comparsa dei comandanti possibili per l'esercito scelto (era la tendina della pergamena).
func _open_commander_menu() -> void:
	var army := _state.army(_selected_army)
	if army == null or army.faction != _player_id:
		return
	if _commander_menu == null:
		_commander_menu = PopupMenu.new()
		_commander_menu.id_pressed.connect(_set_commander)
		add_child(_commander_menu)
	_commander_menu.clear()
	for c in CampaignUiText.eligible_commanders(_state, army):
		_commander_menu.add_item(CampaignUiText.commander_option_text(_state, c), c.id)
	if _commander_menu.item_count == 0:
		return
	_commander_menu.position = DisplayServer.mouse_get_position() - Vector2i(0, 24 * _commander_menu.item_count + 16)
	_commander_menu.popup()


func _set_commander(character_id: int) -> void:
	var army := _state.army(_selected_army)
	if army == null or army.faction != _player_id:
		return
	var r := GameCommands.set_commander(_state, _player_id, army.id, character_id)
	if bool(r["ok"]):
		var chosen := _state.character(character_id)
		var text := Lang.t("%s guida ora %s.") % [chosen.full_name() if chosen != null else Lang.t("Il personaggio"), CampaignUiText.army_title(army).to_lower()]
		var previous := _state.character(int(r.get("precedente", 0)))
		if previous != null:
			text += Lang.t(" %s lascia il comando.") % previous.full_name()
		_toast_show(text)
	else:
		_toast_show(CampaignUiText.order_error_text(_state, str(r["errore"])))
	_rebuild_markers()
	_refresh_army_panel.call_deferred()
	_refresh_court_panel.call_deferred()


## Distintivo del comandante sulla carta della barra in basso (richiesta di Federico dell'11/11/2026): corona del re, insegna
## di erede e principi, del generale, con chi e' nella prima riga del suggerimento.
func _add_commander_badge(entry: Dictionary, army: Army, index: int) -> void:
	var badge := CampaignUiText.commander_badge(_state, army, index)
	if badge.is_empty():
		return
	entry["suggerimento"] = "%s\n%s" % [str(badge["nota"]), str(entry.get("suggerimento", ""))]
	var pennant := OriginalHud.pennant_texture(str(badge["immagine"]))   # dipinto con la veste nuova, altrimenti dell'originale
	if pennant != null:
		entry["distintivo"] = pennant


## Carte delle pile dell'esercito (immagine dell'originale, uomini sotto; nome, uomini e valore nel suggerimento).
func _refresh_army_cards(army: Army) -> void:
	_clear_children(_army_cards)
	_army_card_columns.clear()
	var leader_index := CampaignUiText.commander_stack(_state, army)
	var pennant := OriginalHud.pennant_texture(CampaignUiText.commander_pennant(_state, army)) if leader_index >= 0 else null
	for i in army.stacks.size():
		var st := army.stacks[i]
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		var tip := CampaignUiRetrain.stack_label(_state, army, i)
		if i == leader_index:
			tip = "%s\n%s" % [CampaignUiText.commander_stack_note(_state, army), tip]
			card.add_theme_stylebox_override("panel", _leader_card_style())
		card.tooltip_text = tip + Lang.t("\nClic destro: scheda dell'unità")
		card.gui_input.connect(_on_army_card_input.bind(army.id, i))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(col)
		var holder := Control.new()
		holder.custom_minimum_size = CARD_SIZE
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(holder)
		var tex := PieceArt.unit_card(_data, army.faction, st.unit_id)
		if tex != null:
			var pic := UiTheme.picture(tex, CARD_SIZE)
			pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			holder.add_child(pic)
		else:
			var name_label := Label.new()
			name_label.text = CampaignUiText.unit_name(st.unit_id)
			name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			name_label.add_theme_font_size_override("font_size", 11)
			holder.add_child(name_label)
		if i == leader_index and pennant != null:
			# pennacchio dell'originale appeso alla carta: corona del re, insegna di erede e principi, del generale
			var flag := UiTheme.picture(pennant, PENNANT_SIZE)
			flag.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			flag.position = Vector2(-4, -3)
			flag.size = PENNANT_SIZE
			holder.add_child(flag)
		var men := Label.new()
		men.text = str(st.men)
		men.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		men.add_theme_font_size_override("font_size", 13)
		if not RetrainProcessor.order_at(_state, army.id, i).is_empty():
			men.add_theme_color_override("font_color", UiTheme.INK_BLUE)
		elif i == leader_index:
			men.add_theme_color_override("font_color", UiTheme.INK_TITLE)
		col.add_child(men)
		_army_cards.add_child(card)
		_army_card_columns.append(col)


## Cornice dorata della carta del comandante.
func _leader_card_style() -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.86, 0.74, 0.42, 0.35)
	sb.border_color = Color(0.72, 0.53, 0.12)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(2)
	return sb


func _on_army_card_input(event: InputEvent, army_id: int, index: int) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT or (button.button_index == MOUSE_BUTTON_LEFT and button.double_click):
		_show_unit_info(army_id, index)
		get_viewport().set_input_as_handled()


## Caselle delle pile e comandi per dividere, spostare e unire (solo eserciti del giocatore non crociati).
func _refresh_split_controls(army: Army, mine: bool) -> void:
	_clear_children(_army_stacks_box)
	_army_stack_checks.clear()
	var allowed := mine and not army.is_crusade() and not army.stacks.is_empty()
	var has_partner := allowed and not GameCommands.merge_partners(_state, _player_id, army.id).is_empty()
	var can_split := allowed and (army.stacks.size() > 1 or has_partner)
	# anche un esercito di una sola pila mostra le caselle se si può riaddestrare (o c'è un riaddestramento in corso)
	var can_retrain := allowed and CampaignUiRetrain.has_controls(_state, _player_id, army)
	_army_stacks_box.visible = false   # fase 8: le caselle stanno sotto le carte
	var can_dismiss := mine and CampaignUiDismiss.allowed(_state, _player_id, army)
	_army_split_row.visible = can_split
	_army_retrain_row.visible = can_retrain
	_army_dismiss_row.visible = can_dismiss
	if not (can_split or can_retrain or can_dismiss):
		return
	# fase 8: la casella di ogni pila sta sotto la sua carta (nome, uomini e valore nel suggerimento della carta)
	for i in army.stacks.size():
		var check := CheckBox.new()
		check.focus_mode = Control.FOCUS_NONE
		check.tooltip_text = CampaignUiRetrain.stack_label(_state, army, i)
		check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		check.toggled.connect(_on_stack_check_toggled)
		if i < _army_card_columns.size():
			_army_card_columns[i].add_child(check)
		else:
			_army_stacks_box.add_child(check)
		_army_stack_checks.append(check)
	_refresh_retrain_controls(army)
	_refresh_dismiss_controls(army)
	_army_partner_select.clear()
	for other in GameCommands.merge_partners(_state, _player_id, army.id):
		_army_partner_select.add_item(Lang.t("%s (%d pile)") % [CampaignUiText.army_title(other), other.stacks.size()])
		_army_partner_select.set_item_metadata(_army_partner_select.item_count - 1, other.id)
	_army_partner_select.disabled = _army_partner_select.item_count == 0
	if _army_partner_select.item_count == 0:
		_army_partner_select.add_item(Lang.t("Nessun altro esercito qui"))
		_army_partner_select.set_item_metadata(0, 0)


## Pulsanti del riaddestramento: costo totale nel testo, motivi e tesoro nel tooltip, «Annulla» solo se ci sono ordini.
func _refresh_retrain_controls(army: Army) -> void:
	var info := CampaignUiRetrain.panel_state(_state, _player_id, army, _checked_stacks())
	_army_retrain_button.text = str(info["testo"])
	_army_retrain_button.tooltip_text = str(info["tooltip"])
	_army_retrain_cancel_button.visible = bool(info["annulla_visibile"])
	_army_retrain_cancel_button.text = str(info["annulla_testo"])


func _on_stack_check_toggled(_pressed: bool) -> void:
	var army := _state.army(_selected_army)
	if army != null and _army_retrain_row.visible:
		_refresh_retrain_controls(army)
	if army != null and _army_dismiss_row.visible:
		_refresh_dismiss_controls(army)


## Pulsante del congedo nella pergamena dell'esercito: acceso con almeno una casella spuntata.
func _refresh_dismiss_controls(army: Army) -> void:
	var info := CampaignUiDismiss.button_state(_state, _player_id, army, _checked_stacks())
	var count := CampaignUiDismiss.picked(army, _checked_stacks()).size()
	_army_dismiss_button.text = Lang.t("Congeda le %s scelte%s") % [Lang.t("navi") if army.is_fleet else Lang.t("unità"), (" (%d)" % count) if count > 0 else ""]
	_army_dismiss_button.disabled = not bool(info["attivo"])
	_army_dismiss_button.tooltip_text = str(info["suggerimento"])


## Congedo (ADR-031): chiede conferma per le pile `indices` dell'esercito; il comando parte solo da `_do_dismiss`.
func _ask_dismiss(army_id: int, indices: PackedInt32Array) -> void:
	var army := _state.army(army_id)
	var chosen := CampaignUiDismiss.picked(army, indices)
	if army == null or chosen.is_empty() or not CampaignUiDismiss.allowed(_state, _player_id, army):
		return
	_dismiss_army = army.id
	_dismiss_indices = chosen
	_confirm_ask(Lang.t(CampaignUiDismiss.CONFIRM_TITLE), CampaignUiDismiss.confirm_text(_state, _player_id, army, chosen),
		Lang.t(CampaignUiDismiss.CONFIRM_OK), Lang.t(CampaignUiDismiss.CONFIRM_CANCEL), _do_dismiss)


func _do_dismiss() -> void:
	var army := _state.army(_dismiss_army)
	if army == null:
		return
	var fleet := army.is_fleet
	var r := GameCommands.disband_stacks(_state, _player_id, army.id, _dismiss_indices)
	_dismiss_army = 0
	_dismiss_indices = PackedInt32Array()
	if not bool(r["ok"]):
		_toast_show(CampaignUiText.order_error_text(_state, str(r["errore"])))
		return
	GameAudio.play_sfx("lascia_amico")
	_toast_show(CampaignUiDismiss.done_text(r, fleet))
	_card_pick.clear()
	if bool(r["rimosso"]):
		_group.clear()
		_details = false
		_selected_army = 0
	_minimap_dirty = true
	_refresh_top_bar()
	_rebuild_markers()
	_refresh_army_panel()
	_refresh_province_panel()


func _on_retrain_pressed() -> void:
	var army := _state.army(_selected_army)
	if army == null:
		return
	var r := GameCommands.order_retrain(_state, _player_id, army.id, _checked_stacks())
	_toast_show(CampaignUiRetrain.ordered_text(_state, r))
	_refresh_top_bar()
	_refresh_army_panel.call_deferred()


## «Ripristina»: tutte le pile dell'esercito scelto che hanno perso uomini tornano al completo a fine anno (ADR-046).
func _on_restore_pressed() -> void:
	var army := _state.army(_selected_army)
	if army == null or army.faction != _player_id:
		return
	var r := GameCommands.restore_army(_state, _player_id, army.id)
	_toast_show(CampaignUiRetrain.restored_text(_state, army, r))
	_refresh_top_bar()
	_refresh_army_panel.call_deferred()   # la barra rifà i pulsanti, compreso quello appena premuto


func _on_retrain_cancel_pressed() -> void:
	var army := _state.army(_selected_army)
	if army == null:
		return
	var r := GameCommands.cancel_retrain(_state, _player_id, army.id)
	_toast_show(CampaignUiRetrain.cancelled_text(_state, r))
	_refresh_top_bar()
	_refresh_army_panel.call_deferred()


func _checked_stacks() -> PackedInt32Array:
	var out := PackedInt32Array()
	if not ARMY_PANEL:
		# senza la pergamena le unita' scelte sono le carte della barra in basso
		out = PackedInt32Array(_card_pick)
		out.sort()
		return out
	for i in _army_stack_checks.size():
		if _army_stack_checks[i].button_pressed:
			out.append(i)
	return out


func _chosen_partner() -> int:
	if _army_partner_select.item_count == 0 or _army_partner_select.selected < 0:
		return 0
	return int(_army_partner_select.get_item_metadata(_army_partner_select.selected))


func _after_split_command(r: Dictionary, ok_text: String, select_id: int) -> void:
	if bool(r["ok"]):
		var note := CampaignUiRetrain.refund_note(r)
		_toast_show(ok_text if note == "" else ok_text + " " + note)
		_selected_army = select_id
		if note != "":
			_refresh_top_bar()
	else:
		_toast_show(CampaignUiText.order_error_text(_state, str(r["errore"])))
	_rebuild_markers()
	_refresh_army_panel.call_deferred()


func _on_split_pressed() -> void:
	var army := _state.army(_selected_army)
	if army == null:
		return
	var r := GameCommands.split_army(_state, _player_id, army.id, _checked_stacks())
	var fresh_id := int(r.get("esercito", army.id))
	_after_split_command(r, Lang.t("Esercito diviso: %d pile formano un esercito nuovo.") % int(r.get("pile", 0)), fresh_id if bool(r["ok"]) else army.id)


func _on_transfer_pressed() -> void:
	var army := _state.army(_selected_army)
	var partner := _chosen_partner()
	if army == null or partner == 0:
		_toast_show(Lang.t("Non c'e' un altro esercito della tua fazione in questa regione."))
		return
	var r := GameCommands.transfer_stacks(_state, _player_id, army.id, partner, _checked_stacks())
	var keep := partner if bool(r.get("rimosso", false)) else army.id
	_after_split_command(r, Lang.t("%d pile spostate.") % int(r.get("pile", 0)), keep)


func _on_merge_pressed() -> void:
	var army := _state.army(_selected_army)
	var partner := _chosen_partner()
	if army == null or partner == 0:
		_toast_show(Lang.t("Non c'e' un altro esercito della tua fazione in questa regione."))
		return
	var r := GameCommands.merge_armies(_state, _player_id, army.id, partner)
	_after_split_command(r, Lang.t("Eserciti uniti."), partner if bool(r["ok"]) else army.id)


## Selettore del comandante: solo per un esercito del giocatore con almeno un personaggio idoneo
## nella stessa regione (l'elenco lo decide CampaignUiText.eligible_commanders).
func _refresh_commander_select(army: Army, mine: bool) -> void:
	_army_commander_select.clear()
	var candidates: Array[Character] = []
	if mine:
		candidates = CampaignUiText.eligible_commanders(_state, army)
	_army_commander_row.visible = not candidates.is_empty()
	if candidates.is_empty():
		return
	_army_commander_select.add_item(Lang.t("Cambia comandante…"))
	_army_commander_select.set_item_metadata(0, CHOOSER_PLACEHOLDER)
	for c in candidates:
		_army_commander_select.add_item(CampaignUiText.commander_option_text(_state, c))
		_army_commander_select.set_item_metadata(_army_commander_select.item_count - 1, c.id)
	_army_commander_select.select(0)


func _on_commander_chosen(index: int, options: OptionButton) -> void:
	var character_id := int(options.get_item_metadata(index))
	if character_id == CHOOSER_PLACEHOLDER:
		return
	var army := _state.army(_selected_army)
	if army == null or army.faction != _player_id:
		return
	var r := GameCommands.set_commander(_state, _player_id, army.id, character_id)
	if bool(r["ok"]):
		var chosen := _state.character(character_id)
		var text := Lang.t("%s guida ora %s.") % [chosen.full_name() if chosen != null else Lang.t("Il personaggio"), CampaignUiText.army_title(army).to_lower()]
		var previous := _state.character(int(r.get("precedente", 0)))
		if previous != null:
			text += Lang.t(" %s lascia il comando.") % previous.full_name()
		_toast_show(text)
	else:
		_toast_show(CampaignUiText.order_error_text(_state, str(r["errore"])))
	_refresh_army_panel.call_deferred()
	_refresh_court_panel.call_deferred()


## Pulsante dell'assalto: solo per un esercito del giocatore che assedia.
func _refresh_assault_button(army: Army, mine: bool) -> void:
	var besieging := mine and CampaignUiText.is_besieging(_state, army)
	_army_assault_button.visible = besieging
	if not besieging:
		return
	if _assault_ordered(army):
		_army_assault_button.text = Lang.t("Annulla l'assalto")
		_army_assault_button.disabled = false
		_army_assault_button.tooltip_text = Lang.t("L'esercito torna ad assediare: il castello cede per fame.")
		return
	_army_assault_button.text = Lang.t("Assalta il castello")
	var check := _call_command("can_order_assault", [_state, _player_id, army.id])
	_army_assault_button.disabled = not bool(check.get("ok", false))
	if bool(check.get("ok", false)):
		_army_assault_button.tooltip_text = Lang.t("A fine anno l'esercito assalta il castello invece di attendere.")
	else:
		_army_assault_button.tooltip_text = str(check.get("errore", Lang.t("Assalto non possibile.")))


## Pulsante della guarnigione (richiesta di Federico): barricarsi nel castello della propria provincia, o uscirne.
func _refresh_castle_button(army: Army, mine: bool) -> void:
	var province := _state.province(army.region)
	var c := _state.rules.combat
	var has_castle := province != null and province.level_of(c.castle_family) > 0
	_army_castle_button.visible = mine and not army.is_fleet and has_castle and province.owner == _player_id
	if not _army_castle_button.visible:
		return
	if army.in_castle:
		_army_castle_button.text = Lang.t("Esci dal castello")
		var besieged := _state.is_besieged(army.region)
		_army_castle_button.disabled = besieged
		_army_castle_button.tooltip_text = Lang.t("L'esercito è assediato e non può uscire.") if besieged else Lang.t("L'esercito torna in campo aperto.")
		return
	_army_castle_button.text = Lang.t("Barricati nel castello")
	var check := _call_command("can_garrison_castle", [_state, _player_id, army.id])
	_army_castle_button.disabled = not bool(check.get("ok", false))
	if bool(check.get("ok", false)):
		_army_castle_button.tooltip_text = Lang.t("L'esercito si chiude nel castello: se arriva il nemico lo assedia invece di combattere in campo aperto. Se a fine anno nessuno assedia, esce da solo.")
		if int(check.get("fuori", 0)) > 0:
			_army_castle_button.tooltip_text += Lang.t("\nC'è posto per %d unità: le altre %d restano fuori.") % [int(check.get("dentro", 0)), int(check.get("fuori", 0))]
	else:
		_army_castle_button.tooltip_text = str(check.get("errore", Lang.t("Non è possibile barricarsi.")))


func _on_castle_pressed() -> void:
	_toggle_castle(_state.army(_selected_army))


## Barrica l'esercito nel castello o lo fa uscire (pulsante, sezione del castello, trascinamento).
func _toggle_castle(army: Army) -> void:
	if army == null or army.faction != _player_id:
		return
	if not army.in_castle:
		_garrison_here(army)   # entrano le unita' che ci stanno (richiesta di Federico, 2026-11-10)
		return
	var command := "leave_castle"
	var r := _call_command(command, [_state, _player_id, army.id])
	if bool(r.get("ok", false)):
		if command == "enter_castle":
			_toast_show(Lang.t("%s si barrica nel castello.") % CampaignUiText.army_title(army))
		else:
			_toast_show(Lang.t("%s esce dal castello.") % CampaignUiText.army_title(army))
	else:
		_toast_show(str(r.get("errore", Lang.t("Ordine non possibile."))))
	_rebuild_markers()
	_refresh_army_panel()


func _assault_ordered(army: Army) -> bool:
	var known := CampaignUiText.assault_state(_state, army)
	if known == -1:
		return _assault_local.has(army.id)
	return known == 1


func _on_assault_pressed() -> void:
	var army := _state.army(_selected_army)
	if army == null or army.faction != _player_id:
		return
	if _assault_ordered(army):
		var cancelled := _call_command("cancel_assault", [_state, _player_id, army.id])
		if bool(cancelled.get("ok", false)):
			_assault_local.erase(army.id)
			_toast_show(Lang.t("Assalto annullato: %s resta ad assediare.") % CampaignUiText.army_title(army))
		else:
			_toast_show(str(cancelled.get("errore", Lang.t("Impossibile annullare l'assalto."))))
	else:
		var ordered := _call_command("order_assault", [_state, _player_id, army.id])
		if bool(ordered.get("ok", false)):
			_assault_local[army.id] = true
			_toast_show(Lang.t("%s assalterà il castello a fine anno.") % CampaignUiText.army_title(army))
		else:
			_toast_show(str(ordered.get("errore", Lang.t("Assalto non possibile."))))
	_rebuild_markers()
	_refresh_army_panel()


## Chiama un comando di GameCommands per nome; se la simulazione non lo ha (ancora) restituisce
## un esito negativo invece di rompere l'interfaccia.
func _call_command(command: String, args: Array) -> Dictionary:
	if _command_names.is_empty():
		var commands_script: GDScript = GameCommands
		for m in commands_script.get_script_method_list():
			_command_names[str(m["name"])] = true
	if not _command_names.has(command):
		return {"ok": false, "errore": Lang.t("Comando non disponibile in questa versione: %s") % command}
	var commands: GDScript = GameCommands
	var raw: Variant = commands.callv(command, args)
	if typeof(raw) == TYPE_DICTIONARY:
		var result: Dictionary = raw
		return result
	return {"ok": false, "errore": Lang.t("Esito non valido del comando %s") % command}


func _on_cancel_move_pressed() -> void:
	_cancel_army_move(_selected_army)


func _cancel_army_move(army_id: int) -> void:
	var r := GameCommands.cancel_move(_state, _player_id, army_id)
	if bool(r["ok"]):
		_toast_show(Lang.t("Movimento annullato."))
	else:
		_toast_show(str(r["errore"]))
	_rebuild_markers()
	_refresh_army_panel()


# --- Clic ------------------------------------------------------------------------

## Prende la pedina sotto il puntatore se e' del giocatore (agenti sopra gli eserciti, come per il clic).
func _grab_piece(screen: Vector2) -> void:
	_piece_drag_kind = ""
	_piece_drag_id = 0
	var agent := _state.agent(_army_layer.agent_at(screen))
	if agent != null and agent.faction == _player_id:
		_piece_drag_kind = "agente"
		_piece_drag_id = agent.id
		return
	var army := _state.army(_army_layer.army_at(screen))
	if army != null and army.faction == _player_id:
		_piece_drag_kind = "esercito"
		_piece_drag_id = army.id
		return
	# dal proprio castello si trascina fuori la guarnigione (le pedine nel castello non si vedono): tutta insieme
	var castle_region := _army_layer.castle_at(screen)
	if castle_region != "":
		var inside: Array[int] = []
		for g in _garrison_of(castle_region):
			if g.faction == _player_id:
				inside.append(g.id)
		if not inside.is_empty():
			_piece_drag_kind = "esercito"
			_piece_drag_id = inside[0]
			_group = inside if inside.size() >= 2 else ([] as Array[int])


## Pedina lasciata (come nell'originale, richiesta di Federico): conta su cosa la si posa.
## Esercito: su un esercito proprio si uniscono (subito nella stessa regione, all'arrivo se confinante); su uno straniero lo
## si attacca nella sua regione; in un punto vuoto della propria regione la pedina resta li' (riordino, e l'eventuale
## movimento si annulla); altrove e' un movimento o un attacco. Agente: su un esercito o un agente le missioni possibili
## su quel bersaglio (proposte alla sua fazione, corruzione, assassinio, nozze), nella propria regione il riordino.
func _drop_piece(screen: Vector2) -> void:
	GameAudio.play_sfx("lascia_ostile" if _drag_target_group >= 0 and _drag_target_hostile else "lascia_amico")
	# il pannello di dettaglio si apre solo con il clic, non trascinando (richiesta di Federico)
	var foot := _army_layer.drag_foot(screen)
	if _piece_drag_kind == "agente":
		var agent := _state.agent(_piece_drag_id)
		if agent != null:
			_drop_agent(agent, screen, foot)
		return
	var army := _state.army(_piece_drag_id)
	if army != null:
		_drop_army(army, screen, foot)


func _drop_army(army: Army, screen: Vector2, foot: Vector2) -> void:
	if _is_group_drag() and _drop_group(army, screen):
		return
	var target := _own_settled(_state.army(_army_layer.army_at(screen, army.id)))
	if target != null and target.in_castle and not target.is_fleet and not army.in_castle:
		# su una pedina della guarnigione (disegnata davanti al castello): vale come il castello
		_drop_on_castle(army, target.region)
		return
	if target != null and target.faction == _player_id:
		if target.is_fleet != army.is_fleet:
			_toast_show(Lang.t("Truppe e navi non si uniscono."))
			return
		var r := _call_command("order_merge", [_state, _player_id, army.id, target.id])
		if bool(r.get("ok", false)):
			if bool(r.get("subito", false)):
				_toast_show(Lang.t("%s si unisce a %s.") % [CampaignUiText.army_title(army), CampaignUiText.army_title(target)])
				if _selected_army == army.id:
					_selected_army = target.id
			else:
				_toast_show(Lang.t("%s raggiunge %s a %s e vi si unirà all'arrivo, se c'è posto.") % [CampaignUiText.army_title(army), CampaignUiText.army_title(target), CampaignUiText.region_name(_state, target.region)])
		else:
			_toast_show(CampaignUiText.order_error_text(_state, str(r.get("errore", Lang.t("Unione non possibile.")))))
		_rebuild_markers()
		_refresh_army_panel()
		return
	if target != null:
		if army.is_fleet and target.is_fleet:
			# flotta altrui (richiesta di Federico, 2026-11-13): si attacca proprio lei, anche nella propria zona, con la
			# conferma se non c'e' gia' la guerra, come nell'originale
			_attack_fleet(army, target)
			return
		# esercito straniero: si va nella sua regione (attacco se ostile), anche se la figura sporge su un'altra provincia
		_order_army_to(army, target.region)
		return
	var castle_region := _army_layer.castle_at(screen)
	if castle_region != "":
		if castle_region == army.region and army.in_castle:
			return   # la guarnigione rimessa sul suo castello: resta dentro
		_drop_on_castle(army, castle_region)
		return
	var region := _region_near(_screen_to_world(screen))
	if region == null:
		_toast_show(Lang.t("Nessuna regione in quel punto."))
		return
	if region.id == army.region:
		if army.in_castle:
			# fuori dal castello, nella stessa regione: la guarnigione esce (se non e' assediata)
			if _state.is_besieged(army.region):
				_toast_show(Lang.t("%s è assediato e non può uscire dal castello.") % CampaignUiText.army_title(army))
				return
			_toggle_castle(army)
		_place_piece("esercito", army.id, foot)
		if not army.path.is_empty():
			_cancel_army_move(army.id)
		return
	if CampaignUiPapacy.right_click_action(army, region.id) == CampaignUiPapacy.CLICK_TARGET:
		_set_crusade_target(army, region.id)
		return
	_order_army_to(army, region.id)


## Esercito lasciato sul castello di `region_id` (richiesta di Federico, 2026-11-10): sul proprio si barricano le unita'
## che ci stanno (arrivando, se e' in un'altra provincia), su quello nemico si va ad assediarlo o, con l'assedio gia' in
## corso, si ordina l'assalto. Il piano e' in CampaignUiCastle.drop_plan.
func _drop_on_castle(army: Army, region_id: String) -> void:
	var plan := CampaignUiCastle.drop_plan(_state, _player_id, army, region_id)
	var where := CampaignUiText.region_name(_state, region_id)
	match str(plan["azione"]):
		CampaignUiCastle.BARRICATA:
			_garrison_here(army)
			return
		CampaignUiCastle.VAI_E_BARRICATI:
			var r := _call_command("order_garrison_move", [_state, _player_id, army.id, region_id])
			if bool(r.get("ok", false)):
				_toast_show(Lang.t("%s va a %s e a fine anno si barrica nel castello con le unità che ci stanno.") % [CampaignUiText.army_title(army), where])
			else:
				_toast_show(CampaignUiText.order_error_text(_state, str(r.get("errore", Lang.t("Ordine non possibile.")))))
		CampaignUiCastle.ASSEDIO:
			_order_army_to(army, region_id, false, Lang.t("Se il nemico resta nel castello, a fine anno comincia l'assedio."))
			return
		CampaignUiCastle.ASSALTO:
			var ordered := _call_command("order_assault", [_state, _player_id, army.id])
			if bool(ordered.get("ok", false)):
				_assault_local[army.id] = true
				_toast_show(Lang.t("%s assalterà il castello di %s a fine anno.") % [CampaignUiText.army_title(army), where])
			else:
				_toast_show(str(ordered.get("errore", Lang.t("Assalto non possibile."))))
		_:
			if str(plan["testo"]) != "":
				_toast_show(str(plan["testo"]))
	_rebuild_markers()
	_refresh_army_panel()


## Barrica nel castello della sua provincia le unita' dell'esercito che ci stanno; le altre restano fuori, in un esercito nuovo.
func _garrison_here(army: Army) -> void:
	var r := _call_command("garrison_castle", [_state, _player_id, army.id])
	if bool(r.get("ok", false)):
		var outside := int(r.get("fuori", 0))
		var text := Lang.t("%s si barrica nel castello") % CampaignUiText.army_title(army)
		if outside > 0:
			text += Lang.t(" con %d unità: le altre %d restano fuori, non c'è posto.") % [int(r.get("dentro", 0)), outside]
		else:
			text += "."
		_toast_show(text)
	else:
		_toast_show(CampaignUiText.order_error_text(_state, str(r.get("errore", Lang.t("Ordine non possibile.")))))
	_rebuild_markers()
	_refresh_army_panel()


func _drop_agent(agent: AgentState, screen: Vector2, foot: Vector2) -> void:
	var other_id: int = _army_layer.agent_at(screen, agent.id)
	var other_agent := _state.agent(other_id)
	if other_agent != null and other_agent.faction == _player_id and CampaignUiMoves.agent_in_transit(other_agent):
		other_id = 0   # pedina propria in viaggio: e' disegnata all'arrivo ma ci sara' solo a fine anno
	var army_id: int = 0 if other_id > 0 else _army_layer.army_at(screen)
	if army_id > 0 and _own_settled(_state.army(army_id)) == null:
		army_id = 0
	var region_id := ""
	if other_id > 0:
		var other := _state.agent(other_id)
		region_id = other.region if other != null else ""
	elif army_id > 0:
		var hit := _state.army(army_id)
		region_id = hit.region if hit != null else ""
	if region_id == "":
		other_id = 0
		army_id = 0
		var region := _region_near(_screen_to_world(screen))
		if region == null:
			_toast_show(Lang.t("Nessuna regione in quel punto."))
			return
		region_id = region.id
	var on_piece := other_id > 0 or army_id > 0
	var listing := GameCommands.mission_options(_state, _player_id, agent.id)
	var options: Array = listing.get("missioni", []) if bool(listing.get("ok", false)) else []
	var plan := CampaignUiAgents.click_plan(_state, agent, options, region_id, army_id, other_id)
	var action := str(plan["azione"])
	if action == CampaignUiAgents.PLAN_MENU:
		var entries: Array[Dictionary] = []
		entries.assign(plan["voci"])
		_show_mission_menu(agent, entries, screen)
		return
	if region_id == agent.region:
		# nella propria regione, senza missioni su quel punto: la pedina resta dove la si posa
		_place_piece("agente", agent.id, foot)
		if not agent.path.is_empty():
			_cancel_agent_move(agent)
		elif on_piece:
			_toast_show(Lang.t("%s: nessuna missione possibile su quel bersaglio.") % CampaignUiAgents.title(agent))
		return
	if action == CampaignUiAgents.PLAN_MOVE:
		if _order_agent_move(agent, region_id) and on_piece:
			_toast_show(Lang.t("%s Il bersaglio è fuori portata: quando l'agente arriva, trascinalo di nuovo sopra.") % _toast.text)


## L'esercito come bersaglio di una pedina lasciata, o null se e' un esercito proprio in viaggio: disegnato gia' all'arrivo,
## nella simulazione ci sara' solo a fine anno (movimento fluido, 2026-11-10), quindi si interagisce con lui dall'anno dopo.
func _own_settled(army: Army) -> Army:
	if army != null and army.faction == _player_id and CampaignUiMoves.army_in_transit(army):
		return null
	return army


## Regione nel punto `world` della mappa; sui confini, sui fiumi e sulle coste (pixel senza regione) la piu' vicina entro
## pochi pixel, cosi' una pedina lasciata su una linea non va persa.
func _region_near(world: Vector2) -> CampaignData.Region:
	var x := floori(world.x)
	var y := floori(world.y)
	var region := _region_map.region_at_pixel(x, y)
	if region != null:
		return region
	for radius in range(1, 7):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				region = _region_map.region_at_pixel(x + dx, y + dy)
				if region != null:
					return region
	return null


## Riordino: la pedina resta nel punto della mappa in cui la si posa (`foot`, schermo), finche' non cambia regione.
func _place_piece(kind: String, piece_id: int, foot: Vector2) -> void:
	_call_command("set_piece_spot", [_state, _player_id, kind, piece_id, _screen_to_world(foot)])
	_rebuild_markers()


## Evidenzia la provincia sotto il puntatore mentre si trascina una pedina, come nell'originale: rossa se l'esercito la
## attaccherebbe, verde se ci si muove, azzurra per un agente; nessuna sulla provincia di partenza o fuori dalla mappa.
func _update_drag_target(screen: Vector2) -> void:
	var world := _screen_to_world(screen)
	var region := _region_map.region_at_pixel(floori(world.x), floori(world.y))
	var origin := ""
	var color := DRAG_TARGET_MOVE
	var castle_action := ""
	if _piece_drag_kind == "agente":
		var agent := _state.agent(_piece_drag_id)
		origin = agent.region if agent != null else ""
		color = DRAG_TARGET_AGENT
	else:
		var army := _state.army(_piece_drag_id)
		origin = army.region if army != null else ""
		# sopra un castello (richiesta di Federico, 2026-11-10): si evidenzia la sua provincia anche se e' quella
		# dell'esercito, verde per barricarsi, rossa per assediare o assaltare, grigia se non si puo' fare nulla
		var castle_region := _army_layer.castle_at(screen) if army != null else ""
		if castle_region != "" and not (castle_region == army.region and army.in_castle):
			region = _state.campaign.region(castle_region)
			castle_action = str(CampaignUiCastle.drop_plan(_state, _player_id, army, castle_region)["azione"])
			origin = ""
			if castle_action == CampaignUiCastle.ASSEDIO or castle_action == CampaignUiCastle.ASSALTO:
				color = DRAG_TARGET_ATTACK
			elif castle_action == CampaignUiCastle.NIENTE:
				color = DRAG_TARGET_FAR
		elif army != null and region != null and CampaignUiText.attack_target(_state, army, region.id):
			color = DRAG_TARGET_ATTACK
	var same_region_castle := castle_action == CampaignUiCastle.BARRICATA or castle_action == CampaignUiCastle.ASSALTO
	if region != null and not same_region_castle and not _reach_shown.is_empty() and not _reach_shown.has(region.id):
		color = DRAG_TARGET_FAR
	_drag_target_hostile = color == DRAG_TARGET_ATTACK
	if region == null or region.id == origin:
		_set_drag_target(-1, color)
		return
	_set_drag_target(RegionMap.group_for_index(_region_map.indices_for_region(region)[0]), color)


func _set_drag_target(group: int, color: Color) -> void:
	if group == _drag_target_group or _map_material == null:
		return
	_drag_target_group = group
	_map_material.set_shader_parameter("target_group", group)
	_map_material.set_shader_parameter("target_color", color)


## Regioni raggiungibili quest'anno dalla pedina presa (richiesta di Federico, 2026-11-10): fondo verde per i movimenti,
## azzurro via mare, rosso per gli attacchi; il resto della mappa un po' piu' scuro (CampaignUiMoves, shader reach_tex).
func _show_reach() -> void:
	if _map_material == null or _region_map == null:
		return
	var reach := {}
	if _piece_drag_kind == "agente":
		reach = CampaignUiMoves.agent_reach(_state, _state.agent(_piece_drag_id))
	else:
		reach = CampaignUiMoves.army_reach(_state, _state.army(_piece_drag_id))
	var bytes := PackedByteArray()
	var size := RegionMap.TABLE_SIZE   # 256, o 2048 con la mappa del mondo (ADR-077)
	bytes.resize(size * 4)
	bytes.fill(0)
	for region_id in reach:
		var region := _state.campaign.region(str(region_id))
		if region == null:
			continue
		for index in _region_map.indices_for_region(region):
			if index >= 0 and index < size:
				bytes[index * 4] = int(reach[region_id]) * 50
				bytes[index * 4 + 3] = 255
	var image := Image.create_from_data(size, 1, false, Image.FORMAT_RGBA8, bytes)
	if _reach_texture == null or _reach_texture.get_width() != size:
		_reach_texture = ImageTexture.create_from_image(image)
		_map_material.set_shader_parameter("reach_tex", _reach_texture)
	else:
		_reach_texture.update(image)
	_map_material.set_shader_parameter("reach_on", true)
	_reach_shown = reach


func _hide_reach() -> void:
	_reach_shown = {}
	if _map_material != null:
		_map_material.set_shader_parameter("reach_on", false)


func _end_piece_drag() -> void:
	if _piece_drag_id > 0:
		_army_layer.end_drag()
	_hide_reach()
	_set_drag_target(-1, Color.WHITE)
	_piece_drag_kind = ""
	_piece_drag_id = 0


# --- Selezione multipla (2026-11-10, richiesta di Federico) -----------------------------------------------------------

## Vero se la pedina presa e' un esercito della selezione multipla (almeno due): si muovono tutti insieme.
func _is_group_drag() -> bool:
	return _piece_drag_kind == "esercito" and _group.size() >= 2 and _group.has(_piece_drag_id)


## Gruppo di partenza per Alt+clic e riquadro: quello attuale, o l'esercito proprio gia' selezionato.
func _group_seed() -> Array[int]:
	if not _group.is_empty():
		return _group
	var start: Array[int] = []
	var current := _state.army(_selected_army)
	if current != null and current.faction == _player_id and not current.stacks.is_empty():
		start.append(current.id)
	return start


## Alt+clic: aggiunge o toglie un esercito proprio dalla selezione multipla; altrove vale come un clic normale.
func _on_alt_click(screen: Vector2) -> void:
	var army := _state.army(_army_layer.army_at(screen))
	if army == null or army.faction != _player_id:
		_on_left_click(screen)
		return
	_hide_mission_menu()
	var start := _group_seed()
	var problem := CampaignUiGroup.join_problem(_state, start, army)
	if problem != "":
		_toast_show(problem)
		return
	_group = CampaignUiGroup.toggle(start, army.id)
	GameAudio.play_sfx("seleziona")
	_apply_group_selection(army.id if _group.has(army.id) else 0)


## Fine del riquadro: prende gli eserciti propri al suo interno (dello stesso genere: truppe o navi).
func _finish_box(screen: Vector2) -> void:
	var boxed := _army_layer.armies_in_box(Rect2(_press_pos, Vector2.ZERO).expand(screen))
	var before := _group_seed().size()
	_group = CampaignUiGroup.from_box(_state, _player_id, _group_seed(), boxed)
	if _group.size() == before:
		_toast_show(Lang.t("Nessun tuo esercito nuovo nel riquadro."))
	else:
		GameAudio.play_sfx("seleziona")
	_apply_group_selection(_last_in_group())


func _last_in_group() -> int:
	return _group[_group.size() - 1] if not _group.is_empty() else 0


func _clear_box_selection() -> void:
	_box_selecting = false
	_army_layer.clear_box()


## Dopo un cambio della selezione multipla: il pannello di rassegna mostra `focus` (o l'ultimo scelto), niente pergamena.
func _apply_group_selection(focus: int) -> void:
	_selected_agent = 0
	_details = false
	_selected_army = focus if focus != 0 else _last_in_group()
	if _group.size() == 1:
		_group.clear()   # uno solo: e' la selezione normale
	_rebuild_markers()
	_refresh_army_panel()
	_refresh_agent_panel()
	if _group.size() >= 2:
		var fleets := _state.army(_group[0]).is_fleet
		_toast_show(Lang.t("%d %s: trascinane %s sull'obiettivo o clic destro.") % [_group.size(), Lang.t("flotte scelte") if fleets else Lang.t("eserciti scelti"), Lang.t("una") if fleets else Lang.t("uno")])


## Pedina della selezione multipla lasciata: su un esercito proprio fuori dal gruppo tutti vi si uniscono; su uno
## straniero o su una regione tutti ci vanno. Nella regione della pedina (riordino) o sul castello vale il comportamento
## della sola pedina: restituisce falso.
func _drop_group(army: Army, screen: Vector2) -> bool:
	var target := _own_settled(_state.army(_army_layer.army_at(screen, army.id)))
	if target != null and target.faction == _player_id and not _group.has(target.id):
		if target.is_fleet != army.is_fleet:
			_toast_show(Lang.t("Truppe e navi non si uniscono."))
			return true
		var merged := CampaignUiGroup.merge_all(_state, _player_id, _group, target.id)
		_toast_show(CampaignUiGroup.merge_text(_state, merged, target))
		_group.clear()
		_selected_army = target.id
		_rebuild_markers()
		_refresh_army_panel()
		return true
	if target != null and target.faction != _player_id and target.is_fleet and army.is_fleet:
		_group_attack_fleet(target)
		return true
	var castle_region := _army_layer.castle_at(screen)
	if castle_region == "" and target != null and target.in_castle and not target.is_fleet:
		castle_region = target.region
	if castle_region != "":
		_drop_group_on_castle(castle_region)
		return true
	var region_id := ""
	if target != null:
		region_id = target.region
	else:
		var region := _region_near(_screen_to_world(screen))
		if region == null:
			_toast_show(Lang.t("Nessuna regione in quel punto."))
			return true
		region_id = region.id
	if region_id == army.region:
		return false
	_order_group_to(region_id)
	return true


## Selezione multipla lasciata su un castello: ogni esercito segue il piano del castello (barricarsi finche' c'e' posto,
## andarci e barricarsi, assediare, assaltare); un messaggio riassuntivo.
func _drop_group_on_castle(region_id: String) -> void:
	var counts := {}
	var outside := 0
	var failed := 0
	for army_id in _group.duplicate():
		var army := _state.army(army_id)
		if army == null:
			continue
		var action := str(CampaignUiCastle.drop_plan(_state, _player_id, army, region_id)["azione"])
		var r := {"ok": false}
		match action:
			CampaignUiCastle.BARRICATA:
				r = GameCommands.garrison_castle(_state, _player_id, army.id)
				outside += int(r.get("fuori", 0)) if bool(r.get("ok", false)) else 0
			CampaignUiCastle.VAI_E_BARRICATI:
				r = GameCommands.order_garrison_move(_state, _player_id, army.id, region_id)
			CampaignUiCastle.ASSEDIO:
				r = GameCommands.order_move(_state, _player_id, army.id, PackedStringArray([region_id]))
			CampaignUiCastle.ASSALTO:
				r = GameCommands.order_assault(_state, _player_id, army.id)
				if bool(r.get("ok", false)):
					_assault_local[army.id] = true
		if bool(r.get("ok", false)):
			counts[action] = int(counts.get(action, 0)) + 1
		else:
			failed += 1
	var where := CampaignUiText.region_name(_state, region_id)
	var parts := PackedStringArray()
	if counts.has(CampaignUiCastle.BARRICATA):
		parts.append(Lang.t("%d si barricano nel castello di %s%s") % [counts[CampaignUiCastle.BARRICATA], where, Lang.t(" (%d unità restano fuori)") % outside if outside > 0 else ""])
	if counts.has(CampaignUiCastle.VAI_E_BARRICATI):
		parts.append(Lang.t("%d vanno a %s per barricarsi") % [counts[CampaignUiCastle.VAI_E_BARRICATI], where])
	if counts.has(CampaignUiCastle.ASSEDIO):
		parts.append(Lang.t("%d vanno ad assediare %s") % [counts[CampaignUiCastle.ASSEDIO], where])
	if counts.has(CampaignUiCastle.ASSALTO):
		parts.append(Lang.t("assalto ordinato a %s") % where)
	if failed > 0:
		parts.append(Lang.t("%d non possono (castello pieno o ordine non valido)") % failed)
	_toast_show((Lang.t("Eserciti: ") + "; ".join(parts) + ".") if not parts.is_empty() else Lang.t("Nessun esercito può farlo."))
	_group.clear()
	_rebuild_markers()
	_refresh_army_panel()


## Ordina a tutta la selezione multipla di andare in `region_id` (movimento o attacco), con il messaggio riassuntivo.
func _order_group_to(region_id: String, confirmed: bool = false) -> void:
	if not confirmed:
		var first: Army = _state.army(_group[0]) if not _group.is_empty() else null
		var aimed := CampaignUiAttack.fleet_target_in(_state, first, region_id, _seen)
		if aimed != null:
			_group_attack_fleet(aimed)
			return
		var wars := CampaignUiAttack.new_wars_group(_state, _group, region_id)
		if not wars.is_empty():
			var ids: Array[int] = _group.duplicate()
			_confirm_ask(Lang.t("Attacco"), CampaignUiAttack.prompt_text(_state, _player_id, wars, CampaignUiAttack.region_subject(_state, region_id)),
				Lang.t("Attacca"), Lang.t("Annulla"), func() -> void:
					_group = ids
					_order_group_to(region_id, true))
			return
	var r := CampaignUiGroup.order_move_all(_state, _player_id, _group, region_id)
	_toast_show(CampaignUiGroup.result_text(_state, r, region_id))
	if int(r["pile_riaddestramento"]) > 0:
		_refresh_top_bar()
	_rebuild_markers()
	_refresh_army_panel()


func _on_left_click(screen: Vector2) -> void:
	_hide_mission_menu()
	var site_id := _site_layer.site_at(screen) if _site_layer != null else ""
	if site_id != "":
		_show_site_sheet(site_id)
		return
	_group.clear()   # un clic normale torna alla selezione di una sola pedina
	var agent_id: int = _army_layer.agent_at(screen)
	if agent_id > 0:
		_select_agent(agent_id)
		return
	var army_id: int = _army_layer.army_at(screen)
	var hit := _state.army(army_id)
	if hit != null and hit.in_castle and not hit.is_fleet and not CampaignUiMoves.army_in_transit(hit):
		# pedina della guarnigione, davanti al castello: si sceglie il castello, che mostra tutta la guarnigione
		_select_castle(hit.region)
		return
	if army_id > 0:
		_select_army(army_id)
		return
	var castle_region := _army_layer.castle_at(screen)
	if castle_region != "":
		_select_castle(castle_region)
		return
	_select_at(_screen_to_world(screen))


## Clic sul castello (richiesta di Federico): il pannello di rassegna mostra la guarnigione (tutte le unita' degli eserciti
## nel castello, con i posti occupati); il secondo clic apre la pergamena della provincia con la sezione del castello.
func _select_castle(region_id: String) -> void:
	var region := _state.campaign.region(region_id)
	if region == null:
		return
	GameAudio.play_sfx("seleziona")
	var again := _selected_castle == region_id and _selected != null and _selected.id == region_id
	_group.clear()
	_selected_army = 0
	_selected_agent = 0
	_details = false
	_selected_castle = region_id
	_fold["castello"] = false
	_province_details = again
	_rebuild_markers()
	_refresh_army_panel()
	_refresh_agent_panel()
	_select(region)


# --- Interfaccia originale: barra in basso, minimappa, menu di gioco -------------------------------------------------


func _build_hud() -> void:
	_hud = OriginalHud.new()
	_hud.visible = false
	_ui.add_child(_hud)
	_hud.end_year_pressed.connect(_on_end_year)
	_hud.info_pressed.connect(_on_info_button)
	_hud.build_pressed.connect(func() -> void: _open_modal_for_hud(0))
	_hud.train_pressed.connect(func() -> void: _open_modal_for_hud(1))
	_hud.cycle_province.connect(_cycle_province)
	_hud.minimap_pressed.connect(_on_minimap_pressed)
	_hud.card_pressed.connect(_on_review_card)
	_hud.card_info.connect(_on_review_card_info)
	_hud.card_drag_started.connect(_on_card_drag_started)
	_hud.card_drag_moved.connect(_on_card_drag_moved)
	_hud.card_drag_released.connect(_on_card_drag_released)
	_hud.details_pressed.connect(_on_details_pressed)
	_hud.action_pressed.connect(_on_army_action)
	_hud.dismiss_pressed.connect(func() -> void: _ask_dismiss(_selected_army, PackedInt32Array(_card_pick)))
	_hud.proposals_pressed.connect(_on_proposals_button)
	_hud.shield_pressed.connect(_toggle_map_options)
	_hud.sites_pressed.connect(_toggle_sites_all)
	_hud.help_pressed.connect(func() -> void: _help_panel.visible = not _help_panel.visible)
	_build_game_menu()


## Dimensioni della barra e posizione dei pannelli e delle scritte sopra di essa.
func _layout_hud() -> void:
	if _hud == null:
		return
	_hud.layout(get_viewport().get_visible_rect().size)
	var lift := _hud.bar_height() + 8.0
	_army_panel.offset_top = -lift
	_army_panel.offset_bottom = -lift
	_agent_panel.offset_top = -lift
	_agent_panel.offset_bottom = -lift
	_info_panel.offset_bottom = -lift
	_map_options.offset_bottom = -lift
	_map_options.offset_top = -lift
	_help_label.offset_top = -lift - 26.0
	_help_label.offset_bottom = -lift - 2.0
	_toast_holder.offset_top = 16.0
	_toast_holder.offset_bottom = 16.0
	_warning_panel.offset_top = 50.0
	_warning_panel.offset_bottom = 50.0
	_minimap_dirty = true


## Pulsanti informativi della barra: militare, alleanze, economia, spie (registro), famiglia reale.
func _on_info_button(index: int) -> void:
	GameAudio.play_sfx("pergamena")
	match index:
		0:
			_toggle_standings()
		1:
			_toggle_diplomacy()
		2:
			_toggle_economy()
		3:
			_events_panel.visible = not _events_panel.visible
			if _events_panel.visible:
				if _events_title.text == "":
					_events_title.text = Lang.t("Messaggi e agenti")
				_refresh_agents_tab()
				_fit_events_panel()
		4:
			_toggle_court()


## Carte di costruzione e addestramento: la finestra della provincia scelta (o della prima provincia propria).
func _open_modal_for_hud(tab: int) -> void:
	var province := _state.province(_selected.id) if _selected != null else null
	if province == null or province.owner != _player_id:
		var own := _state.provinces_of(_player_id)
		if own.is_empty():
			return
		_select(_state.campaign.region(own[0].id))
	_open_province_modal(tab)


## Frecce accanto alle carte: provincia propria precedente o successiva, con la vista centrata su di essa.
## Frecce della barra e tasti , e . (con Maiusc solo le province con qualcosa in coda): la provincia propria precedente o
## successiva, con la camera sopra. Con la finestra della provincia aperta la finestra resta sulla stessa scheda e mostra la
## nuova provincia (richiesta di Federico, 2026-11-10: scorrere in fretta le code di tutte le regioni).
func _cycle_province(step: int, only_busy: bool = false) -> void:
	if not only_busy and Input.is_key_pressed(KEY_SHIFT):
		only_busy = true
	var next := CampaignUiQueues.next_province(_state, _player_id, _selected.id if _selected != null else "", step, only_busy)
	if next == "":
		if only_busy:
			_toast_show(Lang.t("Nessuna provincia con qualcosa in coda."))
		return
	var region := _state.campaign.region(next)
	_selected_castle = ""
	_selected_army = 0
	_selected_agent = 0
	_province_details = false
	_refresh_army_panel()
	_refresh_agent_panel()
	_select(region)
	if _anchors.has(region.id):
		_camera.position = _anchors[region.id]
		_clamp_camera()
	if _province_modal.visible:
		_refresh_province_modal()
	if _queues_panel != null and _queues_panel.visible:
		_refresh_queues_panel()


func _on_minimap_pressed(world: Vector2) -> void:
	_camera.position = world
	_clamp_camera()


func _on_details_pressed() -> void:
	if (_selected_army != 0 and ARMY_PANEL) or _selected_agent != 0:
		_details = true
		_refresh_army_panel()
		_refresh_agent_panel()
	elif _selected != null:
		_province_details = true
		_refresh_province_panel()


func _on_review_card(index: int) -> void:
	if _selected_army == 0 and _selected_agent == 0 and _selected_castle == "" and _selected != null:
		# provincia propria: le voci in coda e gli edifici aprono la finestra della provincia
		if index >= 0 and index < _review_tabs.size():
			var action: Variant = _review_tabs[index]
			if typeof(action) == TYPE_DICTIONARY:
				_show_building_info(str(action["edificio"]), int(action["livello"]))
			elif int(action) >= 0:
				_open_province_modal(int(action))
		return
	if _selected_army == 0 and _selected_agent == 0 and _selected_castle != "":
		if index >= 0 and index < _review_cards.size():
			var c: Dictionary = _review_cards[index]
			if not c.is_empty():
				_show_unit_info(int(c["esercito"]), int(c["pila"]))
		return
	var army := _state.army(_selected_army)
	if army == null or index < 0 or index >= army.stacks.size():
		return
	if army.faction == _player_id and not army.is_crusade():
		# esercito o flotta propri: il clic sceglie la carta da separare (trascinandola sulla mappa); clic destro: la scheda
		if _card_pick.has(index):
			_card_pick.erase(index)
		else:
			_card_pick.append(index)
		GameAudio.play_sfx("seleziona")
		_refresh_review()
		return
	_show_unit_info(army.id, index)


## Clic destro su una carta del pannello di rassegna: la scheda dell'unita' (o la stessa azione del clic per le province).
func _on_review_card_info(index: int) -> void:
	var army := _state.army(_selected_army)
	if army != null and army.is_fleet and index >= 0 and index == Admirals.flagship(_state, army):
		_show_admiral_sheet(army)   # ADR-062: la nave dell'ammiraglio (col pennacchio) apre la sua scheda, come la carta del comandante
		return
	if army != null and index >= 0 and index < army.stacks.size():
		var who := CampaignUiText.card_character(_state, army, index)
		if who > 0:
			_show_character_info(who)
		else:
			_show_unit_info(army.id, index)
		return
	if _selected_army == 0 and _selected_agent == 0 and _selected_castle != "" and index >= 0 and index < _review_cards.size():
		var c: Dictionary = _review_cards[index]
		if not c.is_empty():
			var leader := CampaignUiText.card_character(_state, _state.army(int(c["esercito"])), int(c["pila"]))
			if leader > 0:
				_show_character_info(leader)
				return
	_on_review_card(index)


## Trascinamento di carte dell'esercito scelto dalla barra alla mappa (richiesta di Federico, 2026-11-10): se la carta presa
## non era scelta si prende solo lei; un'icona segue il puntatore e le regioni raggiungibili si colorano come per la pedina.
func _on_card_drag_started(index: int) -> void:
	var army := _state.army(_selected_army)
	if army == null or army.faction != _player_id or army.is_crusade() or index < 0 or index >= army.stacks.size():
		return
	if not _card_pick.has(index):
		# niente _refresh_review qui: ridisegnare la barra toglierebbe la carta premuta mentre la si trascina (ADR-148);
		# la cornice di scelta si aggiorna al rilascio
		_card_pick = [index] as Array[int]
	_card_drag_army = army.id
	_piece_drag_kind = "esercito"
	_piece_drag_id = army.id
	_show_reach()
	GameAudio.play_sfx("prendi")
	if _card_drag_icon == null:
		# carta presa: su un piccolo pannello chiaro, cosi' si vede anche sopra il mare
		_card_drag_icon = Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiTheme.PAPER, 0.92)
		sb.border_color = UiTheme.PANEL_BORDER
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 6
		_card_drag_icon.add_theme_stylebox_override("panel", sb)
		_card_drag_icon.size = Vector2(56, 56)
		_card_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_drag_icon.z_index = 20
		var pic := TextureRect.new()
		pic.name = "Carta"
		pic.position = Vector2(4, 4)
		pic.size = Vector2(48, 48)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card_drag_icon.add_child(pic)
		var count := Label.new()
		count.name = "Quante"
		count.position = Vector2(34, 34)
		count.add_theme_font_size_override("font_size", 16)
		count.add_theme_color_override("font_color", Color.WHITE)
		count.add_theme_color_override("font_outline_color", Color.BLACK)
		count.add_theme_constant_override("outline_size", 5)
		if UiTheme.crisp_bold_font() != null:
			count.add_theme_font_override("font", UiTheme.crisp_bold_font())
		_card_drag_icon.add_child(count)
		_ui.add_child(_card_drag_icon)
	var st := army.stacks[_card_pick[0]]
	(_card_drag_icon.get_node("Carta") as TextureRect).texture = PieceArt.unit_card(_data, army.faction, st.unit_id) if AssetLibrary.is_available() else null
	(_card_drag_icon.get_node("Quante") as Label).text = "×%d" % _card_pick.size()
	_card_drag_icon.visible = true
	_on_card_drag_moved(index)


func _on_card_drag_moved(_index: int) -> void:
	if _card_drag_army == 0:
		return
	var pos := get_viewport().get_mouse_position()
	if _card_drag_icon != null:
		_card_drag_icon.position = pos - Vector2(28, 64)
	if _hud.covers(pos):
		_set_drag_target(-1, Color.WHITE)
	else:
		_update_drag_target(pos)


func _on_card_drag_released(_index: int) -> void:
	if _card_drag_army == 0:
		return
	var army := _state.army(_card_drag_army)
	var pos := get_viewport().get_mouse_position()
	_card_drag_army = 0
	if _card_drag_icon != null:
		_card_drag_icon.visible = false
	_end_piece_drag()
	if army != null and _hud.covers(pos):
		_fill_from_cards(army, _hud.review_card_at(pos))   # ADR-147: su un'altra carta uguale la riempie
		_refresh_review()   # cornice delle carte scelte (non si ridisegna durante il trascinamento, ADR-148)
		return
	if army == null:
		return
	var picked := PackedInt32Array(_card_pick)
	var target := _own_settled(_state.army(_army_layer.army_at(pos, army.id)))
	var target_id := target.id if target != null and target.faction == _player_id else 0
	var region := _region_near(_screen_to_world(pos))
	var region_id := region.id if region != null else ""
	if target != null and target_id == 0:
		region_id = target.region   # su un esercito straniero: la sua regione (attacco)
	var plan := CampaignUiSplit.plan(_state, _player_id, army, picked, region_id, target_id)
	if str(plan["azione"]) == CampaignUiSplit.TUTTO:
		# tutte le carte: come trascinare la pedina intera
		_card_pick.clear()
		_drop_army(army, pos, pos)
		return
	var r := CampaignUiSplit.apply(_state, _player_id, army.id, picked, region_id, target_id, _screen_to_world(pos))
	GameAudio.play_sfx("lascia_amico" if bool(r["ok"]) else "lascia_ostile")
	var text := str(r["testo"])
	_toast_show(CampaignUiText.order_error_text(_state, text) if not bool(r["ok"]) else text)
	if bool(r["ok"]):
		_card_pick.clear()
	_rebuild_markers()
	_refresh_army_panel()


## Carte lasciate sulla carta `to_index` dello stesso esercito (ADR-147, manuale p29): la riempiono con i loro uomini se sono
## dello stesso identico tipo; altrove nella barra non succede nulla.
func _fill_from_cards(army: Army, to_index: int) -> void:
	if to_index < 0 or _card_pick.has(to_index) and _card_pick.size() == 1:
		return
	var r := GameCommands.fill_stack(_state, _player_id, army.id, PackedInt32Array(_card_pick), to_index)
	if not bool(r["ok"]):
		GameAudio.play_sfx("lascia_ostile")
		_toast_show(str(r["errore"]))
		return
	GameAudio.play_sfx("unisci")
	var name := UnitTexts.plural_name(army.stacks[int(r["pila"])].unit_id) if int(r["pila"]) >= 0 else ""
	var text := Lang.t("%s: +%d uomini") % [name, int(r["uomini"])]
	if bool(r["piena"]):
		text += Lang.t(", unità al completo")
	if int(r["pile_tolte"]) > 0:
		text += Lang.t("; %d unità svuotate e sciolte") % int(r["pile_tolte"])
	if int(r.get("pile_riaddestramento", 0)) > 0:
		text += Lang.t("; riaddestramento annullato, %d denari restituiti") % int(r["rimborso_riaddestramento"])
	_toast_show(text + ".")
	_card_pick.clear()
	_rebuild_markers()
	_refresh_army_panel()


## Pannello di rassegna (manuale p11): unita' dell'esercito o della flotta scelta, l'agente scelto, gli edifici della provincia
## scelta, altrimenti i messaggi del regno. Con la nebbia di guerra delle province fuori vista non si vede nulla.
func _refresh_review() -> void:
	if _hud == null or _state == null:
		return
	var army := _state.army(_selected_army)
	var agent := _state.agent(_selected_agent)
	var items: Array = []
	var lines := PackedStringArray()
	var title := ""
	_hud.set_dismiss(false)
	_hud.set_actions([])
	if army != null:
		title = CampaignUiText.army_title(army)
		var who := CampaignUiText.commander_caption(_state, army)
		if who != "":
			title += " · %s" % who
		if _card_pick_army != army.id:
			_card_pick_army = army.id
			_card_pick.clear()
		var still: Array[int] = []
		for i in _card_pick:
			if i < army.stacks.size():
				still.append(i)
		_card_pick = still
		var mine := army.faction == _player_id and not army.is_crusade()
		if mine and not _card_pick.is_empty():
			title += Lang.t(" · %d scelte") % _card_pick.size()
		# eserciti altrui senza informazioni di una spia (18/11/2026): solo una stima, niente carte ne' comandante
		var known := SpyIntel.knows_army(_state, _player_id, army)
		if not known:
			title = CampaignUiText.army_title(army)
			lines.append(CampaignUiText.army_estimate(army))
		for i in (army.stacks.size() if known else 0):
			var st := army.stacks[i]
			var card := PieceArt.unit_card(_data, army.faction, st.unit_id) if AssetLibrary.is_available() else null
			var hint := Lang.t("Clic: scegli · trascina sulla mappa per separare o su un'unità uguale per riempirla · «Congeda» per scioglierla · clic destro: scheda") if mine else Lang.t("Clic: scheda dell'unità")
			if CampaignUiText.card_character(_state, army, i) > 0:
				hint += Lang.t(" del comandante, con il ritratto")
			elif army.is_fleet and i == Admirals.flagship(_state, army):
				hint += Lang.t(" dell'ammiraglio, con il ritratto")
			var upgrades := TroopUpgrades.describe(st)
			var entry := {"immagine": card, "misura": OriginalHud.ARMY_CARD, "didascalia": str(st.men), "scelta": mine and _card_pick.has(i),
				"armi": st.weapon, "armatura": st.armour,
				"suggerimento": Lang.t("%s\n%d uomini · valore %d%s\n%s") % [CampaignUiText.unit_name(st.unit_id), st.men, st.value,
					("\n" + upgrades) if upgrades != "" else "", hint]}
			_add_commander_badge(entry, army, i)
			items.append(entry)
		_hud.show_review(title, items, lines, ARMY_PANEL, {}, OriginalHud.ARMY_COLUMNS)   # 10 carte per fila, 2 file (22/11/2026)
		var dismiss := CampaignUiDismiss.button_state(_state, _player_id, army, PackedInt32Array(_card_pick))
		_hud.set_dismiss(bool(dismiss["visibile"]), bool(dismiss["attivo"]), str(dismiss["testo"]), str(dismiss["suggerimento"]))
		_refresh_army_actions(army)
	elif agent != null:
		title = CampaignUiAgents.title(agent)
		lines.append(CampaignUiAgents.describe_agent(_state, agent).get_slice("\n", 0))
		var piece := PieceArt.agent_piece(_data, agent.faction, agent.type_name, false) if AssetLibrary.is_available() else null
		if piece != null:
			items.append({"immagine": piece, "misura": Vector2(40, 60), "suggerimento": CampaignUiAgents.describe_agent(_state, agent)})
		_hud.show_review(title, items, lines, true)
	elif _selected != null and _selected_castle == _selected.id:
		var info := CampaignUiCastle.review(_state, _selected_castle, _player_id, _seen.has(_selected_castle))
		title = str(info["titolo"])
		lines = PackedStringArray(info["righe"])
		# richiesta di Federico (2026-11-11): icona del castello, tipo in grassetto e, accanto, le armate che ci stanno dentro
		# (un gruppo per armata). `_review_cards` ha una voce per ogni voce della barra: {} per le intestazioni.
		_review_cards = []
		for entry in CampaignUiCastle.review_entries(_state, info):
			var c: Dictionary = entry
			if c.has("intestazione"):
				items.append({"intestazione": str(c["intestazione"]), "suggerimento": str(c["suggerimento"]), "affianca": true})
				_review_cards.append({})
				continue
			var card := PieceArt.unit_card(_data, str(c["fazione"]), str(c["unita"])) if AssetLibrary.is_available() else null
			var owner_army := _state.army(int(c["esercito"]))
			var card_item := {"immagine": card, "misura": OriginalHud.CASTLE_CARD, "didascalia": str(c["uomini"]),
				"armi": int(c.get("armi", 0)), "armatura": int(c.get("armatura", 0)),
				"suggerimento": Lang.t("%s\n%d uomini · valore %d\n%s\nClic: scheda dell'unità") % [CampaignUiText.unit_name(str(c["unita"])), int(c["uomini"]), int(c["valore"]),
					CampaignUiText.army_title(owner_army) if owner_army != null else ""]}
			_add_commander_badge(card_item, owner_army, int(c["pila"]))
			items.append(card_item)
			_review_cards.append(c)
		var side := {}
		if int(info["livello"]) > 0:
			var tips := PackedStringArray(info["righe"])
			# i posti della guarnigione stanno gia' nella nota accanto al nome: nel testo resta il resto
			var shown := PackedStringArray()
			for line in lines:
				if not line.begins_with(Lang.t("Guarnigione: ")):
					shown.append(line)
			lines = shown
			if not _review_cards.is_empty():
				tips.append(Lang.t("Secondo clic sul castello: gli eserciti dentro, da scegliere o far uscire."))
			side = {"immagine": _building_icon(str(info["famiglia"]), int(info["livello"]), _selected_castle), "nome": str(info["tipo"]), "nota": str(info["nota"]),
				"suggerimento": CampaignUiText.building_name(_state, str(info["famiglia"]), int(info["livello"])), "suggerimento_nota": "\n".join(tips)}
		_hud.show_review(title, items, lines, true, side)
	elif _selected != null:
		title = CampaignUiText.region_name(_state, _selected.id)
		var province := _state.province(_selected.id)
		if province != null:
			title += " · %s" % CampaignUiText.faction_name(province.owner)
			if province.owner != _player_id and not _seen.has(province.id):
				lines.append(Lang.t("Provincia fuori vista: per conoscerla servono un agente o una provincia confinante."))
			else:
				_review_tabs = []
				if province.owner == _player_id:
					# richiesta di Federico (2026-11-10): prima le voci in coda, con gli anni che mancano, poi gli edifici
					# solo gli edifici in coda: le unita' in addestramento le mostra la carta di addestramento della barra
					# (richiesta di Federico, 2026-11-10)
					var queued: Array[Dictionary] = []
					for q in CampaignUiQueues.entries(province):
						if str(q["tipo"]) == QueueItem.KIND_BUILDING:
							queued.append(q)
					if not queued.is_empty():
						items.append({"intestazione": Lang.t("In coda"), "evidenzia": true})
						_review_tabs.append(-1)
					for q in queued:
						items.append(_queue_review_item(q, province.id))
						_review_tabs.append(0 if str(q["tipo"]) == QueueItem.KIND_BUILDING else 1)
					var summary := CampaignUiQueues.summary(province)
					if summary != "":
						title += " · %s" % summary
					if not queued.is_empty():
						items.append({"intestazione": Lang.t("Costruiti")})
						_review_tabs.append(-1)
				var keys: Array = province.buildings.keys()
				keys.sort()
				for key in keys:
					var level := province.level_of(str(key))
					items.append({"immagine": _building_icon(str(key), level, province.id), "misura": Vector2(54, 40),
						"suggerimento": Lang.t("%s\nClic: la scheda dell'edificio") % CampaignUiText.building_name(_state, str(key), level)})
					_review_tabs.append({"edificio": str(key), "livello": level})
				if items.is_empty():
					lines.append(Lang.t("Nessun edificio."))
		else:
			lines.append(Lang.t("Zona di mare."))
		_hud.show_review(title, items, lines, true)
	else:
		lines.append(CampaignUiText.war_bar_text(CampaignUiText.enemies_of(_state, _player_id)))
		var warning := CampaignUiPapacy.warning_info(_state, _player_id)
		if bool(warning["visibile"]):
			lines.append(str(warning["testo"]))
		lines.append(str(CampaignUiVictory.progress_info(_state, _player_id)["testo"]))
		_hud.show_review("", items, lines, false)
	_refresh_hud_cards()


## Voce in coda per il pannello di rassegna: icona dell'edificio o carta dell'unita', con gli anni che mancano.
func _queue_review_item(q: Dictionary, province_id: String = "") -> Dictionary:
	var building := str(q["tipo"]) == QueueItem.KIND_BUILDING
	var key := str(q["chiave"])
	var years := int(q["anni"])
	var tex: Texture2D = null
	var name_text := ""
	if building:
		tex = _building_icon(key, int(q["livello"]), province_id)
		name_text = CampaignUiText.building_name(_state, key, int(q["livello"]))
	else:
		tex = PieceArt.unit_card(_data, _player_id, key) if AssetLibrary.is_available() else null
		name_text = CampaignUiPapacy.queue_label(_state, key)
	var when := Lang.t("in attesa di fondi") if bool(q["attesa"]) else ("%d %s" % [years, Lang.t("anno") if years == 1 else Lang.t("anni")])
	var first := int(q["posizione"]) == 1
	return {"immagine": tex, "misura": Vector2(54, 40) if building else Vector2(38, 40),
		"didascalia": Lang.t("attesa") if bool(q["attesa"]) else Lang.t("%da") % years,
		"suggerimento": Lang.t("%s %s\n%s · %s\nClic: la finestra della provincia") % [Lang.t("In costruzione:") if building else Lang.t("In addestramento:"), name_text,
			(Lang.t("in corso") if first else Lang.t("%d° in coda") % int(q["posizione"])) if not bool(q["attesa"]) else Lang.t("coda ripetuta"), when]}


## Carte di costruzione e addestramento: la prima voce delle code della provincia scelta (o le immagini dei pulsanti).
func _refresh_hud_cards() -> void:
	var province := _state.province(_selected.id) if _selected != null else null
	var build_tex: Texture2D = AssetLibrary.texture("campmap/buttons/button_build.BIF") if AssetLibrary.is_available() else null
	var train_tex: Texture2D = AssetLibrary.texture("campmap/buttons/button_trainunit.BIF") if AssetLibrary.is_available() else null
	var build_tip := Lang.t("Costruzione: scegli una tua provincia e clicca qui")
	var train_tip := Lang.t("Addestramento: scegli una tua provincia e clicca qui")
	if province != null and province.owner == _player_id:
		build_tip = Lang.t("Costruzione a %s (%d in coda)") % [CampaignUiText.region_name(_state, province.id), province.building_queue.size()]
		train_tip = Lang.t("Addestramento a %s (%d in coda)") % [CampaignUiText.region_name(_state, province.id), province.unit_queue_load()]
		if not province.building_queue.is_empty():
			var b := province.building_queue[0]
			var icon := _building_icon(b.key, b.level, province.id)
			if icon != null:
				build_tex = icon
			build_tip += Lang.t("\nIn corso: %s, %d anni") % [CampaignUiText.building_name(_state, b.key, b.level), b.years_left]
		if not province.unit_queue.is_empty():
			var u := province.unit_queue[0]
			var card := PieceArt.unit_card(_data, _player_id, u.key) if AssetLibrary.is_available() else null
			if card != null:
				train_tex = card
			train_tip += Lang.t("\nIn corso: %s, %d anni") % [CampaignUiPapacy.queue_label(_state, u.key), u.years_left]
	_hud.set_cards(build_tex, build_tip, train_tex, train_tip)


## Minimappa (manuale p11): le zone visibili (nebbia di guerra) con il colore del proprietario, le altre grigie, il mare scuro;
## i mari con flotte proprie un poco piu' azzurri (OriginalHud.sea_color).
func _refresh_minimap() -> void:
	if _hud == null or _region_map == null or _region_map.lbm == null:
		return
	_minimap_dirty = false
	var w := int(OriginalHud.MINI_W)
	var h := int(OriginalHud.MINI_H)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var lbm := _region_map.lbm
	var colors := {}
	var own_seas := OriginalHud.own_fleet_seas(_state, _player_id)
	for y in h:
		for x in w:
			var px := clampi(int((float(x) + 0.5) / float(w) * float(lbm.width)), 0, lbm.width - 1)
			var py := clampi(int((float(y) + 0.5) / float(h) * float(lbm.height)), 0, lbm.height - 1)
			var region := _region_map.region_for_index(lbm.index_at(px, py))
			var c := OriginalHud.SEA
			if region == null:
				c = OriginalHud.LAND.darkened(0.25)
			elif region.is_sea:
				c = OriginalHud.sea_color(_seen.has(region.id), own_seas.has(region.id))
			else:
				c = OriginalHud.LAND
				var p := _state.province(region.id)
				if p != null and _seen.has(region.id):
					if not colors.has(p.owner):
						colors[p.owner] = StateTint.owner_color(_region_map, p.owner)
					c = colors[p.owner]
			img.set_pixel(x, y, c)
	_hud.set_minimap(img, _map_size)


func _update_minimap_view() -> void:
	if _minimap_dirty:
		_refresh_minimap()
	var view := get_viewport().get_visible_rect().size
	var bottom := view.y - _hud.bar_height()
	var corners := PackedVector2Array([Vector2(0, 0), Vector2(view.x, 0), Vector2(view.x, bottom), Vector2(0, bottom)])
	var world := PackedVector2Array()
	for c in corners:
		world.append(_screen_to_world(c))
	_hud.set_view_quad(world)


## Menu di gioco (Esc): come il MenuBox dell'originale, con salvataggio, caricamento e ritorno al menu iniziale.
func _build_game_menu() -> void:
	_game_menu = PanelContainer.new()
	_game_menu.visible = false
	_game_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_game_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_game_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_game_menu.z_index = 8
	_ui.add_child(_game_menu)
	_stack_sheet(_game_menu, null, 8)
	var margin := _margin()
	_game_menu.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = Lang.t("Menu")
	title.theme_type_variation = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var entries := [[Lang.t("Riprendi"), func() -> void: _game_menu.visible = false],
		[Lang.t("Salva la partita (F5 rapido)"), func() -> void: _game_menu.visible = false; _on_save_button()],
		[Lang.t("Carica una partita (F9 rapido)"), func() -> void: _game_menu.visible = false; _saves_panel.open_load()],
		[Lang.t("Comandi e tasti (H)"), func() -> void: _game_menu.visible = false; _help_panel.visible = true],
		[Lang.t("Torna al menu iniziale"), func() -> void: _game_menu.visible = false; _on_menu_button()],
		[Lang.t("Esci dal gioco"), func() -> void: _game_menu.visible = false; _on_quit_button()]]
	for e in entries:
		var b := _make_button(str(e[0]))
		b.pressed.connect(e[1])
		box.add_child(b)
	# Pulsante sempre in vista nell'angolo in alto a destra (segnalazione di Federico dell'11/11/2026: non si capiva come
	# salvare o uscire dalla partita; prima il menu si apriva solo con Esc).
	_menu_corner = _make_button(Lang.t("Menu"))
	_menu_corner.tooltip_text = Lang.t("Salvare, caricare, tornare al menu iniziale o uscire dal gioco (Esc)")
	_menu_corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_menu_corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_menu_corner.offset_left = -12
	_menu_corner.offset_right = -12
	_menu_corner.offset_top = 12
	_menu_corner.add_theme_font_size_override("font_size", 18)
	_menu_corner.z_index = 7
	_menu_corner.pressed.connect(_open_game_menu)
	_ui.add_child(_menu_corner)
	_rulers_corner = _make_button(Lang.t("Regnanti"))
	_rulers_corner.tooltip_text = Lang.t("La sala dei regnanti: i sovrani in carica di tutte le fazioni (K)")
	_rulers_corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_rulers_corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_rulers_corner.offset_left = -92
	_rulers_corner.offset_right = -92
	_rulers_corner.offset_top = 12
	_rulers_corner.add_theme_font_size_override("font_size", 18)
	_rulers_corner.z_index = 7
	_rulers_corner.pressed.connect(_toggle_rulers)
	_ui.add_child(_rulers_corner)


## Scheda di un personaggio con il ritratto (richiesta di Federico dell'11/11/2026): clic destro sulla carta del comandante
## nella barra in basso, o clic su un regnante nella sala dei regnanti.
## Scheda dell'ammiraglio della flotta (ADR-059): ritratto della serie della sua religione, stelle e battaglie.
func _show_admiral_sheet(army: Army) -> void:
	_ensure_character_panel()
	_clear_children(_character_box)
	var head := HBoxContainer.new()
	_character_box.add_child(head)
	var title := Label.new()
	var caption := CampaignUiText.admiral_caption(_state, army)
	title.text = caption.substr(0, 1).to_upper() + caption.substr(1)
	title.theme_type_variation = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _make_button(Lang.t("Chiudi (Esc)"))
	close.pressed.connect(func() -> void: _character_panel.visible = false)
	head.add_child(close)
	_character_box.add_child(UiTheme.divider())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_character_box.add_child(row)
	var tex := PortraitArt.admiral_portrait(_data, army) if AssetLibrary.is_available() else null
	if tex != null:
		var frame := UiTheme.portrait(tex, Vector2(192, 284))
		frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(frame)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 8)
	col.add_child(who)
	var shield := AssetLibrary.faction_shield(army.faction, false) if AssetLibrary.is_available() else null
	if shield != null:
		who.add_child(UiTheme.picture(shield, Vector2(26, 30)))
	var faction_label := Label.new()
	faction_label.text = CampaignUiText.faction_name(army.faction)
	faction_label.theme_type_variation = "Subtitle"
	who.add_child(faction_label)
	for line in CampaignUiText.admiral_lines(_state, army):
		var l := Label.new()
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(330, 0)
		col.add_child(l)
	_character_panel.visible = true



## Schede sovrapposte (segnalazione di Federico del 28/11/2026: aperta la scheda di un re dalla sala dei regnanti, non la
## si poteva chiudere senza chiudere prima la sala). Godot sceglie il destinatario del clic dall'ordine dei nodi, non da
## z_index: una scheda creata prima restava sotto ai clic anche se disegnata sopra. Le schede hanno tutte lo stesso
## z_index e quella che si apre passa in cima all'elenco dei figli di _ui, sopra a disegno e clic. Menu e conferme
## tengono il loro z_index ma salgono anche loro in cima quando compaiono.
const SHEET_Z := 9


func _stack_sheet(top: Control, panel: Control = null, z := SHEET_Z) -> void:
	var p := panel if panel != null else top
	top.z_index = z
	p.visibility_changed.connect(func() -> void:
		if p.visible and top.get_parent() != null:
			top.move_to_front())

func _ensure_character_panel() -> void:
	if _character_panel != null:
		return
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 9
	_ui.add_child(holder)
	_character_panel = PanelContainer.new()
	holder.add_child(_character_panel)
	_stack_sheet(holder, _character_panel)
	var margin := _margin()
	_character_panel.add_child(margin)
	_character_box = VBoxContainer.new()
	_character_box.custom_minimum_size = Vector2(560, 0)
	_character_box.add_theme_constant_override("separation", 8)
	margin.add_child(_character_box)


func _show_character_info(character_id: int) -> void:
	var c := _state.character(character_id)
	if c == null:
		return
	if _character_panel == null:
		var holder := CenterContainer.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.z_index = 9
		_ui.add_child(holder)
		_character_panel = PanelContainer.new()
		holder.add_child(_character_panel)
		_stack_sheet(holder, _character_panel)
		var margin := _margin()
		_character_panel.add_child(margin)
		_character_box = VBoxContainer.new()
		_character_box.custom_minimum_size = Vector2(560, 0)
		_character_box.add_theme_constant_override("separation", 8)
		margin.add_child(_character_box)
	_clear_children(_character_box)
	var head := HBoxContainer.new()
	_character_box.add_child(head)
	var title := Label.new()
	title.text = c.full_name()
	title.theme_type_variation = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _make_button(Lang.t("Chiudi (Esc)"))
	close.pressed.connect(func() -> void: _character_panel.visible = false)
	head.add_child(close)
	_character_box.add_child(UiTheme.divider())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_character_box.add_child(row)
	var tex := PortraitArt.portrait(_data, c) if AssetLibrary.is_available() else null
	if tex != null:
		var frame := UiTheme.portrait(tex, Vector2(192, 284))
		frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(frame)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 8)
	col.add_child(who)
	var shield := AssetLibrary.faction_shield(c.faction, false) if AssetLibrary.is_available() else null
	if shield != null:
		who.add_child(UiTheme.picture(shield, Vector2(26, 30)))
	var faction_label := Label.new()
	faction_label.text = CampaignUiText.faction_name(c.faction)
	faction_label.theme_type_variation = "Subtitle"
	who.add_child(faction_label)
	if c.role != Character.ROLE_PRINCESS or c.command > 0:
		col.add_child(_attribute_row(c))
	for line in CampaignUiText.character_lines(_state, c):
		var l := Label.new()
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(330, 0)
		col.add_child(l)
	var led := CampaignUiText.led_unit(_state, c)
	if not led.is_empty():
		var unit_button := _make_button(Lang.t("Scheda dell'unità che guida"))
		unit_button.tooltip_text = Lang.t("Uomini, valore, armi, armatura e attributi dell'unità con cui combatte.")
		unit_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		unit_button.pressed.connect(func() -> void:
			_character_panel.visible = false
			_show_unit_info(int(led["esercito"]), int(led["pila"])))
		col.add_child(unit_button)
	_character_panel.visible = true
	GameAudio.play_sfx("pergamena")


## Sala dei regnanti (richiesta di Federico dell'11/11/2026, tasto K o «Regnanti» in alto a destra): i capi in carica di tutte
## le fazioni, ciascuno con il ritratto e sotto il nome e chi e'. Il clic su uno apre la sua scheda.
func _toggle_rulers() -> void:
	if _state == null:
		return
	if _rulers_panel != null and _rulers_panel.visible:
		_rulers_panel.visible = false
		return
	if _rulers_panel == null:
		var holder := CenterContainer.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.z_index = 6
		_ui.add_child(holder)
		_rulers_panel = PanelContainer.new()
		holder.add_child(_rulers_panel)
		_stack_sheet(holder, _rulers_panel)
		var margin := _margin()
		_rulers_panel.add_child(margin)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		margin.add_child(box)
		var head := HBoxContainer.new()
		box.add_child(head)
		var title := Label.new()
		title.text = Lang.t("La sala dei regnanti")
		title.theme_type_variation = "Title"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var close := _make_button(Lang.t("Chiudi (Esc)"))
		close.pressed.connect(func() -> void: _rulers_panel.visible = false)
		head.add_child(close)
		_rulers_note = Label.new()
		_rulers_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_rulers_note)
		box.add_child(UiTheme.divider())
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(RULERS_COLUMNS * (RULER_CARD_WIDTH + 10.0) + 14.0, 500)
		box.add_child(scroll)
		_rulers_grid = GridContainer.new()
		_rulers_grid.columns = RULERS_COLUMNS
		_rulers_grid.add_theme_constant_override("h_separation", 10)
		_rulers_grid.add_theme_constant_override("v_separation", 10)
		scroll.add_child(_rulers_grid)
	_clear_children(_rulers_grid)
	var list := CampaignUiText.rulers(_state, _player_id)
	_rulers_note.text = Lang.t("I %d sovrani in carica nell'anno %d. Clic su un regnante: la sua scheda.") % [list.size(), _state.year]
	for e in list:
		_rulers_grid.add_child(_ruler_card(e))
	_rulers_panel.visible = true
	GameAudio.play_sfx("pergamena")


const RULERS_COLUMNS := 7
const RULER_CARD_WIDTH := 132.0


func _ruler_card(e: Dictionary) -> Control:
	var c := _state.character(int(e["personaggio"]))
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	card.custom_minimum_size = Vector2(RULER_CARD_WIDTH, 0)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = Lang.t("%s\n%s\nClic: la scheda con il ritratto") % [str(e["nome"]), str(e["nome_fazione"])]
	card.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_show_character_info(int(e["personaggio"])))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var tex := PortraitArt.portrait(_data, c) if c != null and AssetLibrary.is_available() else null
	if tex != null:
		var pic := UiTheme.portrait(tex, Vector2(96, 142))
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(pic)
	var name_label := Label.new()
	name_label.text = str(e["nome"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 15)
	if UiTheme.bold_font() != null:
		name_label.add_theme_font_override("font", UiTheme.bold_font())
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)
	var who := HBoxContainer.new()
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 4)
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(who)
	var shield := AssetLibrary.faction_shield(str(e["fazione"]), false) if AssetLibrary.is_available() else null
	if shield != null:
		var sh := UiTheme.picture(shield, Vector2(15, 18))
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		who.add_child(sh)
	var faction_label := Label.new()
	faction_label.text = str(e["nome_fazione"])
	faction_label.add_theme_font_size_override("font_size", 13)
	faction_label.add_theme_color_override("font_color", UiTheme.INK_TITLE)
	faction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(faction_label)
	var facts := Label.new()
	facts.text = Lang.t("%d anni · %d %s") % [int(e["eta"]), int(e["province"]), Lang.t("provincia") if int(e["province"]) == 1 else Lang.t("province")]
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	facts.add_theme_font_size_override("font_size", 12)
	facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(facts)
	var relation := Label.new()
	relation.text = str(e["rapporto"])
	relation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	relation.add_theme_font_size_override("font_size", 12)
	var tone := str(e["tono"])
	relation.add_theme_color_override("font_color", UiTheme.INK_BAD if tone == "guerra" else (UiTheme.INK_GOOD if tone == "alleato" else (UiTheme.INK_TITLE if tone == "proprio" else UiTheme.INK)))
	relation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(relation)
	return card


## Apre o chiude il menu di gioco (pulsante «Menu» in alto a destra; Esc fa lo stesso dopo aver chiuso il resto).
func _open_game_menu() -> void:
	_game_menu.visible = not _game_menu.visible


func _on_quit_button() -> void:
	_confirm_ask(Lang.t("Uscire dal gioco"), Lang.t("Chiudere %s?\nLa partita non salvata andrà persa.") % UiTheme.GAME_NAME, Lang.t("Esci"), Lang.t("Resta"), func() -> void:
		get_tree().quit())


## Chiude il pannello dell'esercito o dell'agente (pulsante «Chiudi» o Esc): toglie la selezione della pedina.
func _close_piece_panel() -> void:
	_hide_mission_menu()
	_group.clear()
	_details = false
	_selected_army = 0
	_selected_agent = 0
	_rebuild_markers()
	_refresh_army_panel()
	_refresh_agent_panel()


## Eserciti nel castello della regione, in ordine di id.
func _garrison_of(region_id: String) -> Array[Army]:
	var out: Array[Army] = []
	for a in _state.armies_in(region_id):
		if a.in_castle and not a.is_fleet and not a.stacks.is_empty():
			out.append(a)
	return out


## Sezione del castello nel pannello della provincia: grado, posti della guarnigione, eserciti dentro (selezionabili, con
## l'uscita per i propri) e, per le province proprie, gli eserciti fuori che possono barricarsi.
func _add_castle_section(province: ProvinceState) -> void:
	var c := _state.rules.combat
	var level := province.level_of(c.castle_family)
	if level <= 0:
		return
	var garrison := _garrison_of(province.id)
	if province.owner != _player_id and not _seen.has(province.id):
		var hidden := _add_section(Lang.t("Castello: %s") % CampaignUiText.building_name(_state, c.castle_family, level), "castello", 0)
		var unknown := Label.new()
		unknown.text = Lang.t("Guarnigione sconosciuta: la provincia è fuori vista (nebbia di guerra).")
		unknown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unknown.custom_minimum_size = Vector2(PANEL_WIDTH - 90.0, 0.0)
		unknown.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		hidden.add_child(unknown)
		return
	var content := _add_section(Lang.t("Castello: %s") % CampaignUiText.building_name(_state, c.castle_family, level), "castello", garrison.size())
	var load_line := Label.new()
	var room := Combat.garrison_capacity(_state, province.id)
	if Combat.is_fortress(_state, province.id):
		load_line.text = Lang.t("Guarnigione: %d posti su %d (fortezza: ci entra un'intera armata).") % [Combat.garrison_load(_state, province.id), room]
	else:
		load_line.text = Lang.t("Guarnigione: %d posti su %d (la cavalleria conta doppio).") % [Combat.garrison_load(_state, province.id), room]
	load_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	load_line.custom_minimum_size = Vector2(PANEL_WIDTH - 90.0, 0.0)
	content.add_child(load_line)
	if garrison.is_empty():
		var none := Label.new()
		none.text = Lang.t("Nessun esercito nel castello.") + (Lang.t(" Trascina un tuo esercito sul castello per barricarlo.") if province.owner == _player_id else "")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(PANEL_WIDTH - 90.0, 0.0)
		none.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		content.add_child(none)
	for a in garrison:
		content.add_child(_castle_army_row(a, true))
	if province.owner == _player_id:
		for a in _state.armies_in(province.id):
			if a.faction == _player_id and not a.in_castle and not a.is_fleet and not a.stacks.is_empty():
				content.add_child(_castle_army_row(a, false))


func _castle_army_row(army: Army, inside: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = Lang.t("%s · %d unità, %d uomini%s") % [CampaignUiText.army_title(army), army.stack_count(), army.men_total(), "" if inside else Lang.t(" (fuori)")]
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = label.text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var pick := _make_button(Lang.t("Seleziona"))
	pick.pressed.connect(_select_army.bind(army.id))
	row.add_child(pick)
	if army.faction == _player_id:
		var toggle := _make_button(Lang.pick("Esci", "Leave") if inside else Lang.t("Barricati"))
		if inside:
			toggle.disabled = _state.is_besieged(army.region)
			toggle.tooltip_text = Lang.t("L'esercito è assediato e non può uscire.") if toggle.disabled else Lang.t("L'esercito torna in campo aperto.")
		else:
			var check := _call_command("can_garrison_castle", [_state, _player_id, army.id])
			toggle.disabled = not bool(check.get("ok", false))
			toggle.tooltip_text = Lang.t("Chiude l'esercito nel castello.") if not toggle.disabled else str(check.get("errore", ""))
			if not toggle.disabled and int(check.get("fuori", 0)) > 0:
				toggle.tooltip_text = Lang.t("Entrano %d unità, le altre %d restano fuori.") % [int(check.get("dentro", 0)), int(check.get("fuori", 0))]
		toggle.pressed.connect(_toggle_garrison.bind(army.id))
		row.add_child(toggle)
	return row


func _toggle_garrison(army_id: int) -> void:
	_toggle_castle(_state.army(army_id))
	_refresh_province_panel()


## Clic destro: con un esercito del giocatore selezionato ordina il movimento verso la regione
## cliccata (la validità, per esempio il confine, la decide GameCommands.order_move); se la
## regione è ostile è un ordine d'attacco (freccia rossa, guerra dichiarata a fine anno);
## sulla regione dell'esercito annulla il movimento.
func _on_right_click(screen: Vector2) -> void:
	_hide_mission_menu()
	var selected_agent := _state.agent(_selected_agent)
	if selected_agent != null:
		_on_agent_right_click(selected_agent, screen)
		return
	if _group.size() >= 2:
		var group_world := _screen_to_world(screen)
		var group_region := _region_map.region_at_pixel(floori(group_world.x), floori(group_world.y))
		if group_region == null:
			_toast_show(Lang.t("Nessuna regione in quel punto."))
			return
		_order_group_to(group_region.id)
		return
	var army := _state.army(_selected_army)
	if army == null:
		# clic destro senza pedine selezionate: la pergamena della provincia (come nell'originale)
		var picked := _region_near(_screen_to_world(screen))
		if picked != null:
			_province_details = true
			_select(picked)
		return
	if army.faction != _player_id:
		_toast_show(Lang.t("Non puoi dare ordini a forze di un'altra fazione."))
		return
	var world := _screen_to_world(screen)
	var region := _region_map.region_at_pixel(floori(world.x), floori(world.y))
	if region == null:
		_toast_show(Lang.t("Nessuna regione in quel punto."))
		return
	if region.id == army.region:
		_on_cancel_move_pressed()
		return
	if CampaignUiPapacy.right_click_action(army, region.id) == CampaignUiPapacy.CLICK_TARGET:
		_set_crusade_target(army, region.id)
		return
	_order_army_to(army, region.id)


## Ordina all'esercito di muoversi (o attaccare) verso `region_id`, con il messaggio e l'aggiornamento della mappa. Se
## l'attacco apre una guerra nuova (pace, alleanza, tregua) chiede prima conferma, come nell'originale (CampaignUiAttack);
## una flotta verso una zona con una flotta altrui non alleata attacca quella flotta. `note` si aggiunge al messaggio.
func _order_army_to(army: Army, region_id: String, confirmed: bool = false, note: String = "") -> void:
	if not confirmed:
		var aimed := CampaignUiAttack.fleet_target_in(_state, army, region_id, _seen)
		if aimed != null:
			_attack_fleet(army, aimed)
			return
		var wars := CampaignUiAttack.new_wars_entering(_state, army, region_id)
		if not wars.is_empty():
			_confirm_ask(Lang.t("Attacco"), CampaignUiAttack.prompt_text(_state, _player_id, wars, CampaignUiAttack.region_subject(_state, region_id)),
				Lang.t("Attacca"), Lang.t("Annulla"), func() -> void: _order_army_to(army, region_id, true, note))
			return
	var attack := CampaignUiText.attack_target(_state, army, region_id)
	var lifts_siege := CampaignUiText.is_besieging(_state, army)
	var path := PackedStringArray([region_id])
	var here := _state.campaign.region(army.region)
	if army.is_fleet and here != null and not here.neighbours.has(region_id):
		# flotta verso una zona di mare lontana: percorso piu' breve, percorso per il raggio delle navi ogni anno
		var route := GameCommands.fleet_path(_state, army.id, region_id)
		if not route.is_empty():
			path = route
	var r := GameCommands.order_move(_state, _player_id, army.id, path)
	if bool(r["ok"]):
		var name_text := CampaignUiText.region_name(_state, region_id)
		if bool(r.get("via_mare", false)):
			var chain_text := CampaignUiText.chain_names(_state, r.get("catena", []))
			if attack:
				_toast_show(Lang.t("%s: sbarco ostile a %s via mare (%s); la guerra si dichiara a fine anno.") % [CampaignUiText.army_title(army), name_text, chain_text])
			else:
				_toast_show(Lang.t("%s: trasporto via mare verso %s (%s).") % [CampaignUiText.army_title(army), name_text, chain_text])
		elif path.size() > 1:
			var reach := Combat.fleet_range(_state, army)
			_toast_show(Lang.t("%s: rotta verso %s, %d zone di mare (%d all'anno: %s).") % [CampaignUiText.army_title(army), name_text, path.size(), reach,
				Lang.t("arriva a fine anno") if path.size() <= reach else Lang.t("%d anni") % ceili(float(path.size()) / float(reach))])
		elif attack:
			_toast_show(Lang.t("%s: attacco a %s (la guerra si dichiara a fine anno).") % [CampaignUiText.army_title(army), name_text])
		elif lifts_siege:
			_toast_show(Lang.t("%s: movimento verso %s, l'assedio sarà tolto.") % [CampaignUiText.army_title(army), name_text])
		else:
			_toast_show(Lang.t("%s: movimento verso %s.") % [CampaignUiText.army_title(army), name_text])
	else:
		_toast_show(CampaignUiText.order_error_text(_state, str(r["errore"])))
	if bool(r["ok"]) and note != "":
		_toast_show("%s %s" % [_toast.text, note])
	if bool(r["ok"]) and r.has("rimborso_riaddestramento"):
		_toast_show("%s %s" % [_toast.text, CampaignUiRetrain.refund_note(r)])
		_refresh_top_bar()
	_rebuild_markers()
	_refresh_army_panel()


## Attacco della flotta `army` alla flotta `target` di un'altra fazione (GameCommands.order_naval_attack), con la conferma se
## apre una guerra nuova. Lo scontro e' a fine anno: nella stessa zona senza muoversi, altrove raggiungendo il bersaglio.
func _attack_fleet(army: Army, target: Army, confirmed: bool = false) -> void:
	if not confirmed:
		var wars := CampaignUiAttack.new_wars_naval(_state, army, target)
		if not wars.is_empty():
			_confirm_ask(Lang.t("Attacco navale"), CampaignUiAttack.prompt_text(_state, _player_id, wars, CampaignUiAttack.naval_subject(_state, target)),
				Lang.t("Attacca"), Lang.t("Annulla"), func() -> void: _attack_fleet(army, target, true))
			return
	var r := _call_command("order_naval_attack", [_state, _player_id, army.id, target.id])
	if bool(r.get("ok", false)):
		var text := CampaignUiAttack.naval_order_text(_state, army, target, r)
		if r.has("rimborso_riaddestramento"):
			text += " " + CampaignUiRetrain.refund_note(r)
			_refresh_top_bar()
		_toast_show(text)
	else:
		_toast_show(CampaignUiText.order_error_text(_state, str(r.get("errore", Lang.t("Attacco non possibile.")))))
	_rebuild_markers()
	_refresh_army_panel()


## Le flotte della selezione multipla attaccano tutte la flotta `target`, con una sola conferma.
func _group_attack_fleet(target: Army, confirmed: bool = false) -> void:
	var ids: Array[int] = _group.duplicate()
	if ids.is_empty():
		return
	if not confirmed:
		var wars := CampaignUiAttack.new_wars_naval(_state, _state.army(ids[0]), target)
		if not wars.is_empty():
			_confirm_ask(Lang.t("Attacco navale"), CampaignUiAttack.prompt_text(_state, _player_id, wars, CampaignUiAttack.naval_subject(_state, target)),
				Lang.t("Attacca"), Lang.t("Annulla"), func() -> void:
					_group = ids
					_group_attack_fleet(target, true))
			return
	var done := 0
	var failed := 0
	for id in ids:
		var army := _state.army(id)
		if army == null or not army.is_fleet:
			continue
		if bool(GameCommands.order_naval_attack(_state, _player_id, id, target.id).get("ok", false)):
			done += 1
		else:
			failed += 1
	var text := Lang.t("%d flotte attaccano la flotta %s (%s).") % [done, CampaignUiText.fprep("di", target.faction), CampaignUiText.region_name(_state, target.region)]
	if not _state.at_war(_player_id, target.faction):
		text += Lang.t(" La guerra si dichiara a fine anno.")
	if failed > 0:
		text += Lang.t(" %d non possono.") % failed
	_toast_show(text)
	_rebuild_markers()
	_refresh_army_panel()


# --- Crociate e jihad (fase 5c) --------------------------------------------------------

## Sceglie (o, con `region_id` vuoto, toglie) il bersaglio dell'esercito crociato: la validità la decide
## GameCommands.set_crusade_target, il messaggio CampaignUiPapacy.target_result_text.
func _set_crusade_target(army: Army, region_id: String) -> void:
	var r := GameCommands.set_crusade_target(_state, _player_id, army.id, region_id)
	_toast_show(CampaignUiPapacy.target_result_text(_state, r))
	_rebuild_markers()
	_refresh_army_panel()


## Pulsante «Scegli il bersaglio»: apre l'elenco dei bersagli sopra il pulsante.
func _on_target_button_pressed() -> void:
	var army := _state.army(_selected_army)
	if army == null or army.faction != _player_id or not army.is_crusade():
		return
	var menu := CampaignUiPapacy.target_menu(_state, _player_id, army.id)
	if not bool(menu["ok"]):
		_toast_show(str(menu["errore"]))
		return
	_show_target_menu(army, menu)


func _show_target_menu(army: Army, menu: Dictionary) -> void:
	_clear_children(_mission_menu_box)
	_mission_menu_entries.clear()
	var header := Label.new()
	header.text = str(menu["titolo"])
	header.add_theme_color_override("font_color", SECTION_COLOR)
	_mission_menu_box.add_child(header)
	var entries: Array = menu["voci"]
	if entries.is_empty():
		var none := Label.new()
		none.text = Lang.t("Nessun bersaglio valido in questo momento.")
		_mission_menu_box.add_child(none)
	else:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(430.0, minf(320.0, 34.0 * entries.size() + 6.0))
		_mission_menu_box.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		for entry in entries:
			var d: Dictionary = entry
			var b := _make_button(("» " if bool(d["attuale"]) else "") + str(d["testo"]))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.tooltip_text = Lang.t("Bersaglio: %s (%s).") % [str(d["nome"]), str(d["motivo_testo"])]
			b.pressed.connect(_on_target_entry_pressed.bind(army.id, str(d["regione"])))
			list.add_child(b)
	if str(menu["bersaglio"]) != "":
		var clear_button := _make_button(Lang.t("Togli il bersaglio"))
		clear_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		clear_button.pressed.connect(_on_target_entry_pressed.bind(army.id, ""))
		_mission_menu_box.add_child(clear_button)
	_mission_menu.reset_size()
	var view := get_viewport_rect().size
	var menu_size := _mission_menu.get_combined_minimum_size()
	var anchor_spot := _army_target_button.get_global_rect().position
	var spot := Vector2(anchor_spot.x, anchor_spot.y - menu_size.y - 6.0)
	spot.x = clampf(spot.x, 0.0, maxf(0.0, view.x - menu_size.x))
	spot.y = clampf(spot.y, TOP_BAR_HEIGHT, maxf(TOP_BAR_HEIGHT, view.y - menu_size.y))
	_mission_menu.position = spot
	_mission_menu.visible = true


func _on_target_entry_pressed(army_id: int, region_id: String) -> void:
	_hide_mission_menu()
	var army := _state.army(army_id)
	if army == null or army.faction != _player_id or not army.is_crusade():
		return
	_set_crusade_target(army, region_id)


# --- Agenti (fase 5a) -----------------------------------------------------------------

## Clic destro con un agente selezionato: movimento, annullamento o menu delle missioni. La scelta (e il contenuto
## del menu) la fa CampaignUiAgents.click_plan sulle voci di GameCommands.mission_options.
func _on_agent_right_click(agent: AgentState, screen: Vector2) -> void:
	if agent.faction != _player_id:
		_toast_show(Lang.t("Non puoi dare ordini ad agenti di un'altra fazione."))
		return
	var region_id := ""
	var other_id: int = _army_layer.agent_at(screen, agent.id)
	var other := _state.agent(other_id)
	if other != null:
		region_id = other.region
	else:
		other_id = 0
	var army_id: int = 0 if other_id > 0 else _army_layer.army_at(screen)
	if army_id > 0:
		var hit := _state.army(army_id)
		if hit != null:
			region_id = hit.region
		else:
			army_id = 0
	if region_id == "":
		var world := _screen_to_world(screen)
		var region := _region_map.region_at_pixel(floori(world.x), floori(world.y))
		if region == null:
			_toast_show(Lang.t("Nessuna regione in quel punto."))
			return
		region_id = region.id
	var listing := GameCommands.mission_options(_state, _player_id, agent.id)
	var options: Array = []
	if bool(listing.get("ok", false)):
		options = listing.get("missioni", [])
	var plan := CampaignUiAgents.click_plan(_state, agent, options, region_id, army_id, other_id)
	var action := str(plan["azione"])
	if action == CampaignUiAgents.PLAN_MOVE:
		_order_agent_move(agent, region_id)
	elif action == CampaignUiAgents.PLAN_CANCEL:
		_cancel_agent_orders(agent)
	elif action == CampaignUiAgents.PLAN_MENU:
		var entries: Array[Dictionary] = []
		entries.assign(plan["voci"])
		_show_mission_menu(agent, entries, screen)


func _order_agent_move(agent: AgentState, region_id: String) -> bool:
	var r := GameCommands.order_agent_move(_state, _player_id, agent.id, PackedStringArray([region_id]))
	if bool(r["ok"]):
		_toast_show(CampaignUiAgents.moved_text(_state, agent, region_id, r))
	else:
		_toast_show(CampaignUiText.order_error_text(_state, str(r["errore"])))
	_rebuild_markers()
	_refresh_agent_panel()
	return bool(r["ok"])


## Annulla movimento e missione dell'agente (quello che c'è).
func _cancel_agent_orders(agent: AgentState) -> void:
	var cancelled := false
	if not agent.path.is_empty():
		cancelled = bool(GameCommands.cancel_agent_move(_state, _player_id, agent.id)["ok"])
	if agent.has_mission():
		cancelled = bool(GameCommands.cancel_mission(_state, _player_id, agent.id)["ok"]) or cancelled
	if cancelled:
		_toast_show(Lang.t("%s: ordini annullati.") % CampaignUiAgents.title(agent))
	else:
		_toast_show(Lang.t("%s non ha ordini da annullare.") % CampaignUiAgents.title(agent))
	_rebuild_markers()
	_refresh_agent_panel()


func _on_agent_cancel_move_pressed() -> void:
	_cancel_agent_move(_state.agent(_selected_agent))


func _cancel_agent_move(agent: AgentState) -> void:
	if agent == null or agent.faction != _player_id:
		return
	var r := GameCommands.cancel_agent_move(_state, _player_id, agent.id)
	if bool(r["ok"]):
		_toast_show(Lang.t("%s: movimento annullato.") % CampaignUiAgents.title(agent))
	else:
		_toast_show(str(r["errore"]))
	_rebuild_markers()
	_refresh_agent_panel()


func _on_agent_cancel_mission_pressed() -> void:
	var agent := _state.agent(_selected_agent)
	if agent == null or agent.faction != _player_id:
		return
	var r := GameCommands.cancel_mission(_state, _player_id, agent.id)
	if bool(r["ok"]):
		_toast_show(Lang.t("%s: missione annullata.") % CampaignUiAgents.title(agent))
	else:
		_toast_show(str(r["errore"]))
	_rebuild_markers()
	_refresh_agent_panel()


func _refresh_agent_panel() -> void:
	var agent: AgentState = null
	if _state != null:
		agent = _state.agent(_selected_agent)
	_refresh_review()
	if agent == null or not _details:
		_agent_panel.visible = false
		if _agent_sheet != null:
			_agent_sheet.visible = false
		return
	# la scheda centrata con il ritratto prende il posto della pergamena di solo testo (che la barra copriva)
	_agent_panel.visible = false
	_show_agent_sheet(agent)
	return
	_agent_label.text = CampaignUiAgents.describe_agent(_state, agent)
	var mine := agent.faction == _player_id
	_agent_cancel_move_button.visible = mine
	_agent_cancel_move_button.disabled = agent.path.is_empty()
	_agent_cancel_mission_button.visible = mine
	_agent_cancel_mission_button.disabled = not agent.has_mission()
	_agent_hint.visible = mine
	_agent_panel.visible = true


## Scheda dell'agente (Dettagli o secondo clic): ritratto (la principessa con il suo personaggio, gli altri con
## l'illustrazione del loro tipo), fazione, valore in stelle, eta', ruolo, posizione, viaggio e missione; per gli agenti
## propri i comandi per annullare movimento e missione. Chiudendola l'agente resta selezionato.
func _show_agent_sheet(agent: AgentState) -> void:
	if _agent_sheet == null:
		var holder := CenterContainer.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.z_index = 8
		_ui.add_child(holder)
		_agent_sheet = PanelContainer.new()
		holder.add_child(_agent_sheet)
		_stack_sheet(holder, _agent_sheet)
		var margin := _margin()
		_agent_sheet.add_child(margin)
		_agent_sheet_box = VBoxContainer.new()
		_agent_sheet_box.custom_minimum_size = Vector2(580, 0)
		_agent_sheet_box.add_theme_constant_override("separation", 8)
		margin.add_child(_agent_sheet_box)
	_clear_children(_agent_sheet_box)
	var head := HBoxContainer.new()
	_agent_sheet_box.add_child(head)
	var title := Label.new()
	title.text = CampaignUiAgents.title(agent)
	title.theme_type_variation = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _make_button(Lang.t("Chiudi (Esc)"))
	close.pressed.connect(func() -> void:
		_details = false
		_agent_sheet.visible = false
		_refresh_review())
	head.add_child(close)
	_agent_sheet_box.add_child(UiTheme.divider())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_agent_sheet_box.add_child(row)
	var tex: Texture2D = null
	if AssetLibrary.is_available():
		var c := _state.character(agent.character_id) if agent.character_id > 0 else null
		if c != null:
			tex = PortraitArt.portrait(_data, c)
		if tex == null:
			tex = PortraitArt.agent_portrait(_data, agent)   # ADR-059: ritratto del ruolo, scelto per fazione
		if tex == null:
			tex = AssetLibrary.unit_picture(agent.unit_id)
		if tex == null:
			tex = AssetLibrary.unit_card(agent.unit_id)
	if tex != null:
		var frame := UiTheme.portrait(tex, Vector2(192, 284))
		frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(frame)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 8)
	col.add_child(who)
	var shield := AssetLibrary.faction_shield(agent.faction, false) if AssetLibrary.is_available() else null
	if shield != null:
		who.add_child(UiTheme.picture(shield, Vector2(26, 30)))
	var faction_label := Label.new()
	faction_label.text = CampaignUiText.faction_name(agent.faction)
	faction_label.theme_type_variation = "Subtitle"
	who.add_child(faction_label)
	var lines := CampaignUiAgents.sheet_lines(_state, agent)
	for i in lines.size():
		var l := Label.new()
		l.text = lines[i]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(340, 0)
		if i == 0:
			l.add_theme_color_override("font_color", Color("8a6414"))   # stelle color oro
		col.add_child(l)
	if agent.faction == _player_id:
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		col.add_child(actions)
		var stop := _make_button(Lang.t("Annulla movimento"))
		stop.disabled = agent.path.is_empty()
		stop.pressed.connect(_on_agent_cancel_move_pressed)
		actions.add_child(stop)
		var drop := _make_button(Lang.t("Annulla missione"))
		drop.disabled = not agent.has_mission()
		drop.pressed.connect(_on_agent_cancel_mission_pressed)
		actions.add_child(drop)
		var hint := Label.new()
		hint.text = Lang.t("Trascina l'agente o usa il clic destro: su una regione si muove, su un re, un esercito o un agente sceglie proposte e missioni.")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(340, 0)
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		col.add_child(hint)
	if not _agent_sheet.visible:
		GameAudio.play_sfx("pergamena")
	_agent_sheet.visible = true


## Menu delle azioni dell'agente nel punto cliccato: un pulsante per voce, vicino al cursore.
func _show_mission_menu(agent: AgentState, entries: Array[Dictionary], screen: Vector2) -> void:
	_clear_children(_mission_menu_box)
	_mission_menu_entries = entries
	_menu_agent_id = agent.id
	var header := Label.new()
	header.text = Lang.t("%s: scegli") % CampaignUiAgents.title(agent)
	header.add_theme_color_override("font_color", SECTION_COLOR)
	_mission_menu_box.add_child(header)
	for i in range(entries.size()):
		var entry := entries[i]
		var b := _make_button(str(entry["testo"]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = str(entry.get("tooltip", ""))
		b.pressed.connect(_on_mission_entry_pressed.bind(i))
		_mission_menu_box.add_child(b)
	_mission_menu.reset_size()
	var view := get_viewport_rect().size
	var menu_size := _mission_menu.get_combined_minimum_size()
	var spot := screen + Vector2(8.0, 8.0)
	spot.x = clampf(spot.x, 0.0, maxf(0.0, view.x - menu_size.x))
	spot.y = clampf(spot.y, TOP_BAR_HEIGHT, maxf(TOP_BAR_HEIGHT, view.y - menu_size.y))
	_mission_menu.position = spot
	_mission_menu.visible = true


func _hide_mission_menu() -> void:
	if _mission_menu != null:
		_mission_menu.visible = false


func _on_mission_entry_pressed(index: int) -> void:
	_hide_mission_menu()
	var agent := _state.agent(_menu_agent_id if _menu_agent_id > 0 else _selected_agent)
	if agent == null or agent.faction != _player_id or index < 0 or index >= _mission_menu_entries.size():
		return
	var entry := _mission_menu_entries[index]
	var action := str(entry.get("azione", ""))
	if action == CampaignUiAgents.ACTION_MOVE:
		_order_agent_move(agent, str(entry["regione"]))
	elif action == CampaignUiAgents.ACTION_CANCEL:
		_cancel_agent_orders(agent)
	elif action == CampaignUiAgents.ACTION_MISSION:
		var r := GameCommands.order_mission(_state, _player_id, agent.id, str(entry["tipo"]), entry["bersaglio"])
		if bool(r["ok"]):
			_toast_show(CampaignUiAgents.ordered_text(_state, agent, r))
		else:
			_toast_show(CampaignUiText.order_error_text(_state, str(r["errore"])))
		_rebuild_markers()
		_refresh_agent_panel()


# --- Selezione -----------------------------------------------------------------

func _select_at(world: Vector2) -> void:
	_selected_castle = ""
	var region := _region_map.region_at_pixel(floori(world.x), floori(world.y))
	if region == null or _selected == null or region.id != _selected.id:
		_province_details = false
	elif region != null and _selected != null and region.id == _selected.id:
		_province_details = true   # secondo clic sulla stessa provincia: la pergamena
	_select(region)


func _select(region: CampaignData.Region) -> void:
	_selected = region
	_apply_tint()
	if region == null:
		_border_layer.set_selected_group(-1)
		_info_panel.visible = false
		return
	_border_layer.set_selected_group(RegionMap.group_for_index(_region_map.indices_for_region(region)[0]))
	_refresh_province_panel()


func _describe(region: CampaignData.Region) -> String:
	var lines := PackedStringArray()   # il nome sta nell'intestazione del pannello (_refresh_province_panel)
	if region.is_sea:
		lines.append(Lang.t("Zona di mare"))
	else:
		var owner_id := region.owner
		var province := _state.province(region.id)
		if province != null:
			owner_id = province.owner
		lines.append(Lang.t("Proprietario: %s") % CampaignUiText.faction_name(owner_id))
		for siege_line in CampaignUiText.siege_lines(_state, region.id):
			lines.append(siege_line)
		lines.append(Lang.t("Rendita base: %d") % region.income)
		lines.append(Lang.t("Porto: %s") % (Lang.t("sì") if region.has_port else Lang.t("no")))
		# fase 8: merci e giacimenti come icone dell'originale sotto il testo (_add_goods_rows)
		# SetRegionRebels e' il popolo dei ribelli, non una probabilita' (16/11/2026): il rischio di rivolta sta nella riga della lealta'
		var people := CampaignUiText.rebel_people(region.rebels) if region.rebels > 0 else ""
		if people != "":
			lines.append(Lang.t("Popolo ribelle: %s") % people)
	var neighbour_names := PackedStringArray()
	for n in region.neighbours:
		neighbour_names.append(CampaignUiText.region_name(_state, n))
	lines.append(Lang.t("Confinanti: %s") % _join_or_none(neighbour_names))
	return "\n".join(lines)


func _join_or_none(values: PackedStringArray) -> String:
	if values.is_empty():
		return Lang.t("nessuno")
	return ", ".join(values)


# --- Pannello della provincia -------------------------------------------------------

## Ricostruisce il pannello della provincia selezionata dallo stato attuale.
func _refresh_province_panel() -> void:
	_refresh_review()
	# la finestra di costruzione e arruolamento si aggiorna sempre, anche con la pergamena della provincia chiusa: prima
	# il rinfresco stava in fondo, dopo l'uscita anticipata, e le unita' scelte comparivano in coda solo cambiando regione
	# (segnalazione di Federico dell'11/11)
	if _province_modal != null and _province_modal.visible:
		_refresh_province_modal()
	if _selected == null or not _province_details:
		_info_panel.visible = false
		return
	_info_panel.visible = true
	_province_title.text = CampaignUiText.region_name(_state, _selected.id)
	var owner_id := ""
	if not _selected.is_sea:
		var owned := _state.province(_selected.id)
		owner_id = owned.owner if owned != null else _selected.owner
	_province_shield.texture = AssetLibrary.faction_shield(owner_id) if owner_id != "" else null
	_province_shield.visible = owner_id != ""
	_info_label.text = _describe(_selected)
	_info_label.visible = true
	_clear_children(_province_box)
	_clear_children(_province_tab_box)
	_province_tab_box.visible = false
	if _selected.is_sea:
		return
	var province := _state.province(_selected.id)
	if province == null:
		_add_goods_rows(_selected)
		return
	# Pergamena a schede (richiesta di Federico dell'11/11, dal mockup della veste nuova): le stesse sezioni di prima,
	# raggruppate in Provincia, Castello, Governo ed Edifici invece che in un'unica colonna da scorrere.
	var own := province.owner == _player_id
	var tabs := CampaignUiText.province_tabs(own)
	if not tabs.has(_province_tab):
		_province_tab = CampaignUiText.TAB_PROVINCE
	_add_tab_row(tabs)
	_info_label.visible = false
	match _province_tab:
		CampaignUiText.TAB_PROVINCE:
			_add_facts_table(_info_label.text)
			_add_goods_rows(_selected)
			if own:
				var st := CampaignUiText.loyalty_status(_state, province)
				var line := _add_text(CampaignUiText.loyalty_summary(_state, province), _loyalty_color(str(st["stato"])))
				if UiTheme.bold_font() != null:
					line.add_theme_font_override("font", UiTheme.bold_font())
				line.tooltip_text = Lang.t("Dettagli nella scheda Governo")
				line.mouse_filter = Control.MOUSE_FILTER_PASS
				_add_tax_row(province)
				_add_income_section(province)
			_add_religion_section(province)
		CampaignUiText.TAB_CASTLE:
			# la guarnigione si vede anche da una provincia confinante o da una flotta vicina (20/11/2026)
			if SpyIntel.knows_province(_state, _player_id, province.id) or SpyIntel.watches_region(_state, _player_id, province.id):
				_add_castle_section(province)
			else:
				_add_text(CampaignUiText.garrison_estimate(_state, province), UiTheme.INK_FAINT)
			_add_agents_section(province)
		CampaignUiText.TAB_GOVERNMENT:
			_add_governance_section(province)
		CampaignUiText.TAB_BUILDINGS:
			if own:
				_add_queues(province)
			if SpyIntel.knows_province(_state, _player_id, province.id):
				_add_built_section(province)
			else:
				_add_text(Lang.t("Edifici sconosciuti: manda una spia nella provincia, o fagliela spiare, per vederli."), UiTheme.INK_FAINT)
	if own:
		_add_province_actions(province)


## Riga delle schede in testa alla pergamena della provincia: quella aperta e' chiara e in rilievo.
func _add_tab_row(tabs: Array) -> void:
	var row := _province_tab_box
	row.visible = true
	for tab in tabs:
		var b := _make_button(CampaignUiText.province_tab_name(tab))
		_style_tab_button(b, tab == _province_tab)
		b.pressed.connect(_on_province_tab_pressed.bind(tab))
		row.add_child(b)


## Aspetto di una scheda (pergamena della provincia e finestra di costruzione, arruolamento e mercenari): linguetta di
## carta, quella aperta chiara con il filo in alto, a tutta larghezza.
func _style_tab_button(b: Button, active: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTheme.PAPER_LIGHT if active or state == "hover" else UiTheme.PAPER_DARK
		if state == "disabled":
			sb.bg_color = UiTheme.PAPER_DARK.darkened(0.08)   # scheda vuota (per esempio niente flotta senza porto)
		sb.border_color = UiTheme.INK_TITLE if active else UiTheme.PANEL_BORDER
		sb.set_border_width_all(1)
		sb.border_width_top = 3 if active else 1
		sb.border_width_bottom = 0 if active else 1
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		b.add_theme_stylebox_override(state, sb)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(color_name, UiTheme.INK_TITLE if active else UiTheme.INK)
	b.add_theme_color_override("font_disabled_color", UiTheme.INK_FAINT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Schede della finestra della provincia (Costruzione, Arruolamento, Mercenari), uguali a quelle della pergamena.
func _refresh_modal_tab_row() -> void:
	_clear_children(_modal_tab_row)
	for i in _province_tabs.get_tab_count():
		var b := _make_button(_province_tabs.get_tab_title(i))
		_style_tab_button(b, i == _province_tabs.current_tab)
		b.pressed.connect(func() -> void:
			_province_tabs.current_tab = i
			_refresh_modal_tab_row())
		_modal_tab_row.add_child(b)


## Dati della provincia su due colonne (nome in inchiostro tenue, valore in grassetto); le righe lunghe, come i
## confinanti, restano a tutta larghezza sotto la tabella.
func _add_facts_table(text: String) -> void:
	var facts := CampaignUiText.fact_rows(text)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 2)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for pair in facts["coppie"]:
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key := Label.new()
		key.text = str(pair[0])
		key.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(key)
		var value := Label.new()
		value.text = str(pair[1])
		if UiTheme.bold_font() != null:
			value.add_theme_font_override("font", UiTheme.bold_font())
		cell.add_child(value)
		grid.add_child(cell)
	if grid.get_child_count() > 0:
		_province_box.add_child(grid)
	else:
		grid.free()
	for line in facts["righe"]:
		_add_text(str(line))


func _on_province_tab_pressed(tab: int) -> void:
	if tab == _province_tab:
		return
	_province_tab = tab
	_refresh_province_panel.call_deferred()


func _clear_children(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _add_text(text: String, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_WIDTH - 70.0, 0.0)
	if color != Color.WHITE:
		l.add_theme_color_override("font_color", color)
	_province_box.add_child(l)
	return l


func _add_header(text: String) -> void:
	_province_box.add_child(UiTheme.divider())
	var l := _add_text(text)
	l.theme_type_variation = "Subtitle"


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE   # Invio e barra spaziatrice non devono premere i pulsanti
	return b


## Sezione richiudibile: intestazione a pulsante e contenitore per le voci.
func _add_section(title: String, key: String, count: int) -> VBoxContainer:
	var closed: bool = _fold.get(key, false)
	_province_box.add_child(UiTheme.divider())
	var mark := "▸" if closed else "▾"
	var header := _make_button("%s %s (%d)" % [mark, title, count])
	header.theme_type_variation = "Section"
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.pressed.connect(_on_fold_pressed.bind(key))
	_province_box.add_child(header)
	var content := VBoxContainer.new()
	content.visible = not closed
	_province_box.add_child(content)
	return content


func _on_fold_pressed(key: String) -> void:
	_fold[key] = not bool(_fold.get(key, false))
	_refresh_province_panel.call_deferred()


## Voce di un elenco: pulsante a tutta larghezza, testo troncato, dettagli nel tooltip.
func _add_option_button(parent: Container, text: String, tooltip: String, enabled: bool) -> Button:
	var b := _make_button(text)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.disabled = not enabled
	b.tooltip_text = tooltip
	parent.add_child(b)
	return b


func _add_tax_row(province: ProvinceState) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = Lang.t("Tassa:")
	row.add_child(label)
	var options := OptionButton.new()
	options.focus_mode = Control.FOCUS_NONE
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.tooltip_text = Lang.t("Il livello di tassa modifica il reddito agricolo della provincia e, subito, la sua lealtà.")
	for level in range(_rules.tax_multipliers.size()):
		options.add_item(CampaignUiText.tax_option_text(_state, level), level)
	options.select(clampi(province.tax_level, 0, options.item_count - 1))
	options.item_selected.connect(_on_tax_selected)
	row.add_child(options)
	_province_box.add_child(row)


func _on_tax_selected(index: int) -> void:
	if _selected == null:
		return
	var r := GameCommands.set_tax(_state, _player_id, _selected.id, index)
	_after_command(r, Lang.t("Tassa %s.") % CampaignUiText.tax_name(index).to_lower())


## Governatore (assegnazione e revoca del titolo) e lealtà della provincia. Il governatore compare
## solo se la fazione ha una dinastia; la lealtà solo se la simulazione la espone (fase 4b).
func _add_governance_section(province: ProvinceState) -> void:
	var governor_lines := CampaignUiText.governor_lines(_state, province.id)
	var loyalty_lines := CampaignUiText.loyalty_lines(province)
	if governor_lines.is_empty() and loyalty_lines.is_empty():
		return
	_add_header(Lang.t("Governo e lealtà"))
	var governor_now := _state.governor_of(province.id)
	if governor_now != null and governor_lines.size() >= 2:
		# fase 8: nome e titolo in testo, stelle e attributi come icone
		_add_text("\n".join(governor_lines.slice(0, 2)))
		_province_box.add_child(_attribute_row(governor_now))
	elif not governor_lines.is_empty():
		_add_text("\n".join(governor_lines))
	if _state.has_dynasty(province.owner):
		var choices := CampaignUiText.governor_choices(_state, province)
		var governor := _state.governor_of(province.id)
		var row := HBoxContainer.new()
		# richiesta di Federico del 20/11/2026: elenco a comparsa con prima i presenti nella provincia e in un altro colore
		# chi ha gia' un titolo (la tendina standard non permette colori per voce)
		var options := _make_button((Lang.t("Assegna il titolo a…") + "  ▾") if not choices.is_empty() else Lang.t("Nessun personaggio idoneo"))
		options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		options.clip_text = true
		options.alignment = HORIZONTAL_ALIGNMENT_LEFT
		options.tooltip_text = Lang.t("Assegna il titolo di governatore: chi lo aveva lo perde e la sua lealtà cala di %d.") % _rules.dynasty.revoke_loyalty_drop
		options.disabled = choices.is_empty()
		options.pressed.connect(_open_governor_menu.bind(options))
		row.add_child(options)
		var revoke := _make_button(Lang.t("Revoca"))
		revoke.disabled = governor == null
		revoke.tooltip_text = Lang.t("Toglie il titolo al governatore: la sua lealtà cala di %d.") % _rules.dynasty.revoke_loyalty_drop
		if governor != null:
			revoke.pressed.connect(_on_revoke_title.bind(governor.id))
		row.add_child(revoke)
		_province_box.add_child(row)
	if province.owner == _player_id and _state.has_dynasty(province.owner):
		_add_offices_section(province)
	if not loyalty_lines.is_empty():
		_add_loyalty_panel(province)


## Colore dello stato della lealtà (CampaignUiText.LOYALTY_*).
static func _loyalty_color(status: String) -> Color:
	match status:
		CampaignUiText.LOYALTY_LOYAL:
			return UiTheme.INK_GOOD
		CampaignUiText.LOYALTY_RESTLESS:
			return Color("a35a10")
		CampaignUiText.LOYALTY_REVOLT:
			return UiTheme.INK_BAD
	return UiTheme.INK


## Lealtà resa chiara (richiesta di Federico del 16/11/2026): stato a parole e a colori, barra da 0 al massimo con la soglia di
## rivolta e l'obiettivo, rischio di rivolta a fine anno in percentuale, tendenza e ciò che la determina.
func _add_loyalty_panel(province: ProvinceState) -> void:
	var st := CampaignUiText.loyalty_status(_state, province)
	var color := _loyalty_color(str(st["stato"]))
	_add_header(Lang.t("Lealtà e rischio di rivolta"))
	var head := _add_text(Lang.t("Lealtà: %s — %d su %d") % [str(st["titolo"]), int(st["valore"]), int(st["massimo"])], color)
	if UiTheme.bold_font() != null:
		head.add_theme_font_override("font", UiTheme.bold_font())
	_province_box.add_child(_loyalty_meter(st, color))
	_add_text(Lang.t("Linea rossa: soglia di rivolta (%d) · linea blu: obiettivo (%d)") % [int(st["soglia"]), int(st["obiettivo"])], UiTheme.INK_FAINT)
	var risk := _add_text(str(st["rischio_testo"]), UiTheme.INK_BAD if float(st["rischio"]) > 0.0 else UiTheme.INK_GOOD)
	if UiTheme.bold_font() != null:
		risk.add_theme_font_override("font", UiTheme.bold_font())
	_add_text(Lang.t("Tendenza: %s") % str(st["tendenza"]), UiTheme.INK_FAINT)
	var terms: Array = st["termini"]
	if not terms.is_empty():
		_add_text(Lang.t("Cosa la determina:"), UiTheme.INK_FAINT)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 22)
		grid.add_theme_constant_override("v_separation", 0)
		for pair in terms:
			var name := Label.new()
			name.text = str(pair[0])
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(name)
			var value := Label.new()
			var amount := int(pair[1])
			value.text = str(amount) if str(pair[0]) == CampaignUiText.term_label("base") else CampaignUiText.signed(amount)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if amount != 0 and str(pair[0]) != CampaignUiText.term_label("base"):
				value.add_theme_color_override("font_color", UiTheme.INK_GOOD if amount > 0 else UiTheme.INK_BAD)
			grid.add_child(value)
		_province_box.add_child(grid)
	_add_text(str(st["spiegazione"]), UiTheme.INK_FAINT)


## Barra della lealtà: da 0 al massimo, zona rossa sotto la soglia di rivolta, riempimento fino al valore attuale nel colore
## dello stato, tacca scura sulla soglia e tacca blu sull'obiettivo.
func _loyalty_meter(st: Dictionary, color: Color) -> Control:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(PANEL_WIDTH - 70.0, 18.0)
	bar.tooltip_text = Lang.t("Lealtà %d su %d · sotto %d rischio di rivolta · obiettivo %d") % [int(st["valore"]), int(st["massimo"]), int(st["soglia"]), int(st["obiettivo"])]
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.draw.connect(func() -> void:
		var w := bar.size.x
		var h := bar.size.y
		var top := 3.0
		var bh := h - 6.0
		var maxv := maxf(1.0, float(st["massimo"]))
		var x_of := func(v: float) -> float: return clampf(v / maxv, 0.0, 1.0) * w
		bar.draw_rect(Rect2(0, top, w, bh), Color(UiTheme.INK_FAINT, 0.18))
		bar.draw_rect(Rect2(0, top, x_of.call(float(st["soglia"])), bh), Color(UiTheme.INK_BAD, 0.16))
		bar.draw_rect(Rect2(0, top, x_of.call(float(st["valore"])), bh), Color(color, 0.85))
		bar.draw_rect(Rect2(0, top, w, bh), Color(UiTheme.INK, 0.6), false, 1.0)
		var xs: float = x_of.call(float(st["soglia"]))
		bar.draw_line(Vector2(xs, 0), Vector2(xs, h), UiTheme.INK_BAD, 2.0)
		var xt: float = x_of.call(float(st["obiettivo"]))
		bar.draw_line(Vector2(xt, 0), Vector2(xt, h), UiTheme.INK_BLUE, 2.0))
	return bar


## Cariche di Stato che compaiono in questa provincia (manuale p25: le sblocca l'edificio che vi si trova): nome, bonus,
## titolare con gli attributi, selettore per assegnarla e pulsante di revoca.
func _add_offices_section(province: ProvinceState) -> void:
	var offices := CampaignUiText.offices_seated_in(_state, province)
	if offices.is_empty():
		return
	_add_header(Lang.t("Cariche di Stato"))
	for o in offices:
		var label := DynastyProcessor.office_label(_state, province.owner, o.building)
		var bonus := CampaignUiText.office_bonus_text(o)
		var holder := DynastyProcessor.office_holder(_state, province.owner, o.building)
		var head := "%s — %s" % [label, bonus] if bonus != "" else label
		_add_text("%s\n%s" % [head, (Lang.t("Titolare: %s") % holder.full_name()) if holder != null else Lang.t("Vacante")])
		if holder != null:
			_province_box.add_child(_attribute_row(holder))
		var candidates := CampaignUiText.eligible_officers(_state, province.owner, o.building)
		var row := HBoxContainer.new()
		# come per il governatore (20/11/2026): elenco a comparsa, presenti per primi, in blu chi ha gia' una carica
		var options := _make_button((Lang.t("Concedi la carica a…") + "  ▾") if not candidates.is_empty() else Lang.t("Nessun personaggio idoneo"))
		options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		options.clip_text = true
		options.alignment = HORIZONTAL_ALIGNMENT_LEFT
		options.tooltip_text = Lang.t("Concedi la carica di %s: chi la deteneva la perde e la sua lealtà cala di %d; una sola carica a testa.") % [label, _rules.dynasty.revoke_loyalty_drop]
		options.disabled = candidates.is_empty()
		options.pressed.connect(_open_office_menu.bind(options, o.building))
		row.add_child(options)
		var revoke := _make_button(Lang.t("Revoca"))
		revoke.disabled = holder == null
		revoke.tooltip_text = Lang.t("Toglie la carica: la lealtà del titolare cala di %d.") % _rules.dynasty.revoke_loyalty_drop
		if holder != null:
			revoke.pressed.connect(_on_revoke_office.bind(holder.id))
		row.add_child(revoke)
		_province_box.add_child(row)


func _open_office_menu(anchor: Control, building: String, seat_region: String = "") -> void:
	var where := seat_region
	if where == "" and _selected != null:
		where = _selected.id
	_open_character_menu(anchor, CampaignUiText.office_choices(_state, _player_id, building, where),
		Lang.t("In blu chi ha già un'altra carica: ricevendo questa la lascia."), _assign_office.bind(building))


func _assign_office(character_id: int, building: String) -> void:
	var r := GameCommands.assign_office(_state, _player_id, character_id, building)
	var chosen := _state.character(character_id)
	var who := chosen.full_name() if chosen != null else Lang.t("Il personaggio")
	_after_command(r, Lang.t("%s riceve la carica di %s.") % [who, DynastyProcessor.office_label(_state, _player_id, building)])


func _on_revoke_office(character_id: int) -> void:
	var holder := _state.character(character_id)
	var label := DynastyProcessor.office_label(_state, _player_id, holder.office) if holder != null and holder.office != "" else ""
	var r := GameCommands.revoke_office(_state, _player_id, character_id)
	var who := holder.full_name() if holder != null else Lang.t("Il personaggio")
	_after_command(r, Lang.t("Carica di %s revocata a %s: la sua lealtà cala di %d.") % [label, who, _rules.dynasty.revoke_loyalty_drop])


const CHOOSER_TITLED_INK := UiTheme.INK_BLUE   ## voci di chi ha gia' un titolo o una carica
const CHOOSER_MENU_MAX_HEIGHT := 440.0


## Elenco a comparsa per il titolo della provincia scelta (richiesta di Federico del 20/11/2026): presenti per primi, in blu
## chi governa gia' un'altra provincia (la lascera'). Ordine e gruppi da CampaignUiText.governor_choices.
func _open_governor_menu(anchor: Control) -> void:
	if _selected == null:
		return
	_open_character_menu(anchor, CampaignUiText.governor_choices(_state, _state.province(_selected.id)),
		Lang.t("In blu chi governa già un'altra provincia: ricevendo questo titolo la lascia."), _assign_governor)


## Elenco a comparsa di personaggi (governatore e cariche, 20/11/2026): «Nella provincia» con chi vi si trova, poi
## «Altrove»; in blu le voci «titolate», con `note` in fondo. Voci da CampaignUiText (*_choices: personaggio, qui, titolato,
## testo). Un clic chiude l'elenco e chiama `on_pick` con l'id del personaggio.
func _open_character_menu(anchor: Control, choices: Array[Dictionary], note: String, on_pick: Callable) -> void:
	if choices.is_empty() or anchor == null:
		return
	if _governor_menu != null and is_instance_valid(_governor_menu):
		_governor_menu.queue_free()
	_governor_menu = PopupPanel.new()
	_governor_menu.add_theme_stylebox_override("panel", UiTheme._flat(UiTheme.PAPER, UiTheme.LEATHER, 1, 6, 8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var height := 0.0
	var widest := 0.0
	var group := ""
	var titled := false
	for ch in choices:
		var here := bool(ch["qui"])
		var name_group := "qui" if here else "altrove"
		if name_group != group:
			group = name_group
			var head := Label.new()
			head.text = Lang.t("Nella provincia") if here else Lang.t("Altrove")
			head.add_theme_color_override("font_color", UiTheme.INK_TITLE)
			if UiTheme.bold_font() != null:
				head.add_theme_font_override("font", UiTheme.bold_font())
			box.add_child(head)
			height += 28.0
		var c: Character = ch["personaggio"]
		var b := _governor_menu_row(str(ch["testo"]), bool(ch["titolato"]))
		b.pressed.connect(_on_character_picked.bind(c.id, on_pick))
		box.add_child(b)
		widest = maxf(widest, b.get_combined_minimum_size().x)
		height += 31.0
		titled = titled or bool(ch["titolato"])
	if titled and note != "":
		var note_label := Label.new()
		note_label.text = note
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_label.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		box.add_child(note_label)
		height += 48.0
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(box)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r := anchor.get_global_rect()
	var view := get_viewport().get_visible_rect().size
	var width := clampf(widest + 24.0, maxf(r.size.x, 420.0), view.x * 0.6)   # larghezza del testo piu' lungo
	scroll.custom_minimum_size = Vector2(width, minf(height, CHOOSER_MENU_MAX_HEIGHT))
	_governor_menu.add_child(scroll)
	_ui.add_child(_governor_menu)
	var size := Vector2i(int(width) + 16, int(scroll.custom_minimum_size.y) + 16)
	var pos := Vector2i(int(r.position.x), int(r.end.y) + 2)
	if pos.y + size.y > int(view.y):
		pos.y = maxi(0, int(r.position.y) - size.y - 2)
	pos.x = clampi(pos.x, 0, maxi(0, int(view.x) - size.x))
	_governor_menu.popup(Rect2i(pos, size))


## Voce dell'elenco dei personaggi: testo a sinistra su fondo di pergamena, scura al passaggio del mouse.
func _governor_menu_row(text: String, titled: bool) -> Button:
	var b := _make_button(text)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var ink := CHOOSER_TITLED_INK if titled else UiTheme.INK
	for state_name in ["font_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(state_name, ink)
	b.add_theme_color_override("font_hover_color", UiTheme.INK_TITLE)
	b.add_theme_color_override("font_hover_pressed_color", UiTheme.INK_TITLE)
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(0, 0, 0, 0)
	empty.content_margin_left = 8
	empty.content_margin_right = 8
	empty.content_margin_top = 4
	empty.content_margin_bottom = 4
	var hover := UiTheme._flat(UiTheme.PAPER_DARK, UiTheme.PAPER_DARK, 0, 4, 8, 4)
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("hover_pressed", hover)
	return b


func _on_character_picked(character_id: int, on_pick: Callable) -> void:
	if _governor_menu != null and is_instance_valid(_governor_menu):
		_governor_menu.hide()
		_governor_menu.queue_free()
	_governor_menu = null
	on_pick.call(character_id)


func _assign_governor(character_id: int) -> void:
	if _selected == null:
		return
	var r := GameCommands.assign_title(_state, _player_id, character_id, _selected.id)
	var chosen := _state.character(character_id)
	var who := chosen.full_name() if chosen != null else Lang.t("Il personaggio")
	_after_command(r, Lang.t("%s governa ora %s.") % [who, CampaignUiText.region_name(_state, _selected.id)])


func _on_revoke_title(character_id: int) -> void:
	var holder := _state.character(character_id)
	var province_name := CampaignUiText.region_name(_state, holder.title) if holder != null else ""
	var r := GameCommands.revoke_title(_state, _player_id, character_id)
	var who := holder.full_name() if holder != null else Lang.t("Il personaggio")
	_after_command(r, Lang.t("Titolo di %s revocato a %s: la sua lealtà cala di %d.") % [province_name, who, _rules.dynasty.revoke_loyalty_drop])


## Composizione religiosa (fase 5b): religioni presenti in ordine decrescente, quella del proprietario evidenziata,
## gli eretici in rosso oltre la soglia della rivolta eretica, e lo zelo.
func _add_religion_section(province: ProvinceState) -> void:
	_add_header(Lang.t("Religione"))
	for row in CampaignUiReligion.section_rows(_state, province):
		var color := Color.WHITE
		if bool(row["rosso"]):
			color = BAD_COLOR
		elif bool(row["proprietario"]):
			color = OWNER_RELIGION_COLOR
		var label := _add_text(str(row["testo"]), color)
		if bool(row["rosso"]):
			label.tooltip_text = Lang.t("Con troppi eretici la rivolta della provincia è eretica e più probabile.")
			label.mouse_filter = Control.MOUSE_FILTER_PASS
		_prefix_icon(label, UiIcons.icon("religioni", str(row["chiave"]), CampaignUiReligion.religion_label(str(row["chiave"])), UiIcons.SMALL_SIZE, " "))
	var zeal := _add_text(CampaignUiReligion.zeal_text(_state, province))
	_prefix_icon(zeal, UiIcons.icon("attributi", "zeal", Lang.t("Zelo"), UiIcons.SMALL_SIZE, " "))


## Fase 8: righe «Merci» e «Giacimenti» con le icone dell'originale (nome nel suggerimento).
func _add_goods_rows(region: CampaignData.Region) -> void:
	for entry in [[Lang.t("Merci"), "merci", region.trade_goods], [Lang.t("Giacimenti"), "risorse", region.resources]]:
		var names := PackedStringArray(entry[2])
		if names.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var title := Label.new()
		title.text = str(entry[0])
		title.theme_type_variation = "Subtitle"
		title.custom_minimum_size = Vector2(96, 0)
		row.add_child(title)
		var flow := UiIcons.icon_flow(str(entry[1]), names)
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(flow)
		_province_box.add_child(row)


## Mette `icon` a sinistra dell'etichetta `label` (gia' nel pannello), in una riga.
func _prefix_icon(label: Label, icon: Control) -> void:
	var parent := label.get_parent()
	var index := label.get_index()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	parent.move_child(row, index)
	parent.remove_child(label)
	label.custom_minimum_size.x = maxf(0.0, label.custom_minimum_size.x - 30.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(icon)
	row.add_child(label)


## Fase 8: attributi di un personaggio come icone dell'originale con il valore (nome per esteso nel suggerimento).
func _attribute_row(c: Character, with_command: bool = true) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	if with_command:
		row.add_child(UiIcons.stars(c.stars(_state.rules, _state.campaign)))
	var attrs := [[Character.ATTR_DREAD, Lang.t("Terrore")], [Character.ATTR_PIETY, Lang.t("Pietà")], [Character.ATTR_ACUMEN, Lang.t("Acume")]]
	if c.role == Character.ROLE_LEADER:
		attrs.append([Character.ATTR_INFLUENCE, Lang.t("Influenza")])
	else:
		attrs.append([Character.ATTR_LOYALTY, Lang.t("Lealtà")])
	for a in attrs:
		row.add_child(UiIcons.attribute(str(a[0]), CampaignUiText.attr_value(_state, c, str(a[0])), str(a[1])))
	return row


func _add_income_section(province: ProvinceState) -> void:
	_add_header(Lang.t("Reddito annuo della provincia"))
	var income := Economy.province_income(_state, province)
	_add_text("\n".join(CampaignUiText.income_lines(income)))


func _add_built_section(province: ProvinceState) -> void:
	var keys: Array = province.buildings.keys()
	keys.sort()
	var content := _add_section(Lang.t("Edifici costruiti"), "costruiti", keys.size())
	if keys.is_empty():
		var none := Label.new()
		none.text = Lang.t("nessuno")
		content.add_child(none)
		return
	# fase 8d: le tessere dell'originale, il nome nel suggerimento (senza esportazione, il nome scritto)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(flow)
	for key in keys:
		var family_id: String = key
		var level := province.level_of(family_id)
		var name_text := CampaignUiText.building_name(_state, family_id, level)
		var tex := _building_icon(family_id, level, province.id)
		if tex == null:
			var l := Label.new()
			l.text = name_text
			content.add_child(l)
			continue
		var pic := UiTheme.picture(tex, BUILT_ICON_SIZE)
		pic.tooltip_text = Lang.t("%s\nClic: la scheda dell'edificio") % name_text
		pic.mouse_filter = Control.MOUSE_FILTER_STOP
		pic.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pic.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_show_building_info(family_id, level))
		flow.add_child(pic)


## `province_id`: provincia dell'edificio (fortezza degli Auror, ADR-076; grafica per la cultura d'origine della regione,
## RegionStyle, 22/11/2026). Vuoto = la regione selezionata; senza regione resta la grafica della fazione del giocatore.
func _building_icon(family_id: String, level: int, province_id: String = "") -> Texture2D:
	if not AssetLibrary.is_available() or _buildings == null:
		return null
	if province_id == "" and _selected != null and not _selected.is_sea:
		province_id = _selected.id
	var prov := _state.province(province_id) if province_id != "" else null
	if prov == null:
		province_id = ""
	if province_id != "" and family_id == _state.rules.combat.castle_family:
		var fortress := FortressArt.icon(province_id)
		if fortress != null:
			return fortress
	var owner_id := prov.owner if prov != null and prov.owner != "" else _player_id
	if family_id == _state.rules.combat.castle_family:
		# castelli della fazione che possedeva la regione all'inizio, anche dopo la conquista (Federico, 22/11/2026)
		var style_faction := RegionStyle.castle_faction(_state, province_id) if province_id != "" else _player_id
		var styled := CastleStyle.icon(style_faction, _state.rules.combat.castle_tier(maxi(1, level)))
		if styled != null:
			return styled
	var fam: BuildingType = _buildings.get_family(family_id)
	var lv: BuildingType.Level = fam.get_level(maxi(1, level)) if fam != null else null
	var religion := _player_religion()
	if province_id != "":
		religion = RegionStyle.building_religion(_state, province_id, fam, owner_id, religion)
	return BuildingArt.icon(lv.label if lv != null else family_id, family_id, religion)


## Pulsanti che aprono la finestra della provincia sulla scheda della costruzione o dell'arruolamento (richiesta di Federico:
## schede chiuse o finestre distinte, per non avere tutto insieme appena si seleziona la provincia).
func _add_province_actions(province: ProvinceState) -> void:
	_province_box.add_child(UiTheme.divider())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var buildable := 0
	for e in _building_entries(province):
		if bool(e["ok"]):
			buildable += 1
	var recruitable := 0
	for e in _unit_entries(province):
		if bool(e["ok"]):
			recruitable += 1
	var build := _make_button(Lang.t("Costruisci (%d)") % buildable)
	build.tooltip_text = Lang.t("Edifici costruiti, in coda e da costruire, con le icone.")
	build.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build.pressed.connect(_open_province_modal.bind(0))
	row.add_child(build)
	var mercs := GameCommands.mercenary_options(_state, _player_id, province.id).size()
	var recruit := _make_button(Lang.t("Arruola (%d)") % recruitable)
	recruit.tooltip_text = Lang.t("Unità, agenti e navi arruolabili qui, con le carte. Clic destro su una carta: la scheda.")
	recruit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recruit.pressed.connect(_open_province_modal.bind(1))
	row.add_child(recruit)
	var hire := _make_button(Lang.t("Mercenari (%d)") % mercs)
	hire.tooltip_text = Lang.t("Compagnie di mercenari presenti nella provincia: si assoldano subito.")
	hire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hire.pressed.connect(_open_province_modal.bind(2))
	row.add_child(hire)
	_province_box.add_child(row)


func _add_queues(province: ProvinceState) -> void:
	_add_header(Lang.t("Coda di costruzione (%d/%d)") % [province.building_queue.size(), _rules.max_building_queue])
	if province.building_queue.is_empty():
		_add_text(Lang.t("vuota"))
	for i in range(province.building_queue.size()):
		var item := province.building_queue[i]
		var text := Lang.t("%d. %s · %d anni%s") % [i + 1, CampaignUiText.building_name(_state, item.key, item.level), item.years_left, Lang.t(" (in corso)") if i == 0 else ""]
		_add_queue_row(GameCommands.QUEUE_BUILDING, i, text, item.cost_paid)
	_add_header(Lang.t("Coda di reclutamento (%d/%d)%s") % [province.unit_queue_load(), _rules.max_unit_queue, Lang.t(" · si ripete") if province.repeats_units() else ""])
	if province.unit_queue.is_empty() and province.repeat_pending.is_empty():
		_add_text(Lang.t("vuota"))
	for i in range(province.unit_queue.size()):
		var item := province.unit_queue[i]
		var text := Lang.t("%d. %s · %d anni%s") % [i + 1, CampaignUiPapacy.queue_label(_state, item.key), item.years_left, Lang.t(" (in corso)") if i == 0 else ""]
		_add_queue_row(GameCommands.QUEUE_UNIT, i, text, item.cost_paid)
	for line in _repeat_pending_lines(province):
		var waiting := _add_text(line)
		waiting.add_theme_color_override("font_color", UiTheme.INK_BAD)


## Agenti presenti nella provincia (propri e altrui): una riga ciascuno e, per i propri, il pulsante che li seleziona.
func _add_agents_section(province: ProvinceState) -> void:
	var lines := CampaignUiAgents.province_lines(_state, province.id, _player_id)
	if lines.is_empty():
		return
	var content := _add_section(Lang.t("Agenti presenti"), "agenti", lines.size())
	for line in lines:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(line["testo"])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if bool(line["mio"]):
			var pick := _make_button(Lang.t("Seleziona"))
			pick.tooltip_text = Lang.t("Seleziona l'agente sulla mappa: poi clic destro per muoverlo o per una missione.")
			pick.pressed.connect(_select_agent.bind(int(line["id"])))
			row.add_child(pick)
		content.add_child(row)


func _add_queue_row(queue_name: String, index: int, text: String, refund: int) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = text
	row.add_child(label)
	var cancel := _make_button(Lang.t("Annulla"))
	cancel.tooltip_text = Lang.t("Rimborso: %d denari") % refund
	cancel.pressed.connect(_on_cancel_queue.bind(queue_name, index))
	row.add_child(cancel)
	_province_box.add_child(row)


func _on_cancel_queue(queue_name: String, index: int) -> void:
	if _selected == null:
		return
	var r := GameCommands.cancel_queue_item(_state, _player_id, _selected.id, queue_name, index)
	if bool(r["ok"]):
		_after_command(r, Lang.t("Annullato: rimborsati %d denari.") % int(r["rimborso"]))
	else:
		_after_command(r, "")


## Edifici costruibili: il filtro toglie solo ciò che non sarà mai possibile (livello massimo,
## fazione, religione, risorsa o porto mancanti); il resto è mostrato, disabilitato con il motivo.
func _building_entries(province: ProvinceState) -> Array[Dictionary]:
	var region: CampaignData.Region = _data.region(province.id)
	var entries: Array[Dictionary] = []
	for fam in _buildings.families:
		var lv := fam.get_level(province.level_of(fam.id) + 1)
		if lv == null or not lv.allows_faction(_player_id) or not _religion_allows(fam):
			continue
		if fam.has_type("PORT") and (region == null or not region.has_port):
			continue
		var has_resources := true
		for res in lv.resources:
			if region == null or not region.resources.has(res):
				has_resources = false
		if not has_resources:
			continue
		var check := GameCommands.can_queue_building(_state, _player_id, province.id, fam.id)
		var ok := bool(check["ok"])
		var cost := _state.rules.traits.building_cost(_player_id, lv)   # ADR-089
		var years := _state.rules.traits.building_years(_player_id, lv)
		if ok:
			cost = int(check["costo"])
			years = int(check["anni"])
		var title := CampaignUiText.building_name(_state, fam.id, lv.level)
		var tip := Lang.t("Costo %d denari, %d anni.") % [cost, years]
		if not ok:
			tip = str(check["errore"])
			var needs := CampaignUiText.requires_text(_state, lv.requires)
			if needs != "":
				tip += Lang.t("\nRichiede: %s") % needs
		entries.append({"ok": ok, "family": fam.id, "level": lv.level, "label": lv.label, "title": title, "cost": cost, "years": years,
			"text": Lang.t("%s · %d denari, %d anni") % [title, cost, years], "tip": "%s\n%s" % [title, tip]})
	return entries


func _on_queue_building(family_id: String) -> void:
	if _selected == null:
		return
	var r := GameCommands.queue_building(_state, _player_id, _selected.id, family_id)
	_after_command(r, Lang.t("Costruzione messa in coda: %s.") % CampaignUiText.building_name(_state, family_id, int(r.get("livello", 1))))


## Unità reclutabili: stesso criterio degli edifici (il filtro tiene fuori ciò che la
## provincia, la fazione o l'epoca non permettono mai; i requisiti in edifici e il tesoro
## appaiono come motivo del pulsante disabilitato).
func _unit_entries(province: ProvinceState) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var region: CampaignData.Region = _data.region(province.id)
	if region == null:
		return entries
	# Truppe e navi, poi gli agenti (emissari, spie, assassini, religiosi): stesso filtro, etichetta diversa.
	var candidates: Array[UnitType] = AurorUnits.elite_first(_units.military())   # ADR-074: le unita' esclusive per prime
	for u in _units.agents():
		if CampaignUiAgents.is_recruitable_agent(u) or CampaignUiPapacy.unit_kind(u) != "":
			candidates.append(u)
	for u in candidates:
		if u.unique:
			continue   # Ankalagon non si arruola
		var free := _state.rules.lifts_unit_limits(_player_id, u)   # gli Auror vedono ogni truppa e nave
		if not free and (not u.recruitable_by(_player_id) or not u.available_in_period(_state.era)):
			continue
		var crusade_kind := CampaignUiPapacy.unit_kind(u)
		if crusade_kind != "" and not CampaignUiPapacy.recruit_visible(_state, _player_id, crusade_kind):
			continue   # la crociata è dei cattolici, il jihad dei musulmani
		if not free and (not u.allows_region(region.id) or not u.allows_culture(GameCommands.culture_key(region.culture))):
			continue
		if u.is_ship() and not region.has_port:
			continue
		var is_agent_unit := CampaignUiAgents.is_recruitable_agent(u)
		var check := GameCommands.can_queue_unit(_state, _player_id, province.id, u.id)
		var ok := bool(check["ok"])
		var cost := _state.rules.traits.unit_cost(_player_id, u)   # ADR-089
		var years := _state.rules.traits.unit_years(_player_id, u)
		if ok:
			cost = int(check["costo"])
			years = int(check["anni"])
		var tip := Lang.t("Costo %d denari, %d anni.") % [cost, years]
		if not ok:
			tip = str(check["errore"])
			var needs := CampaignUiText.requires_text(_state, u.requires)
			if needs != "":
				tip += Lang.t("\nRichiede: %s") % needs
		var text := Lang.t("%s · %d denari, %d anni") % [CampaignUiText.unit_name(u.id), cost, years]
		if crusade_kind != "":
			text = CampaignUiPapacy.recruit_text(u, crusade_kind, cost, years, "" if ok else str(check["errore"]))
			tip = CampaignUiPapacy.recruit_tip(crusade_kind, tip)
		elif is_agent_unit:
			text = CampaignUiAgents.recruit_text(u, cost, years)
			tip = CampaignUiAgents.recruit_tip(u, tip)
		else:
			tip += Lang.t("\nUomini: %d · mantenimento: %d") % [u.men, u.support_cost]
		var short_name := CampaignUiText.agent_unit_name(u.id) if (is_agent_unit or crusade_kind != "") else CampaignUiText.unit_name(u.id)
		entries.append({"ok": ok, "unit": u.id, "name": short_name, "cost": cost, "years": years, "text": text,
			"tip": "%s\n%s" % [short_name, tip], "agente": is_agent_unit or crusade_kind != "", "nave": u.is_ship(),
			"uomini": u.men if not (u.is_ship() or u.is_agent() or is_agent_unit or crusade_kind != "") else 0})
	return entries


func _on_queue_unit(unit_id: String) -> void:
	if _selected == null:
		return
	var r := GameCommands.queue_unit(_state, _player_id, _selected.id, unit_id)
	_after_command(r, Lang.t("Reclutamento in coda: %s.") % CampaignUiPapacy.queue_label(_state, unit_id))


## Filtro di visualizzazione: stessa regola di GameCommands per la religione (che è privata).
func _religion_allows(family: BuildingType) -> bool:
	if family.religions.is_empty():
		return true
	var cf: CampaignData.Faction = _data.faction(_player_id)
	if cf == null or cf.religion == "":
		return true
	return GameCommands.building_allows_religion(family, GameCommands.religion_key(cf.religion))


## Esito di un comando dal pannello: messaggio, barra aggiornata, pannello ricostruito dopo il segnale.
func _after_command(result: Dictionary, ok_text: String) -> void:
	if bool(result["ok"]):
		_toast_show(ok_text)
	else:
		_toast_show(CampaignUiText.order_error_text(_state, str(result["errore"])))
	_refresh_top_bar()
	_refresh_province_panel.call_deferred()
	_refresh_court_panel.call_deferred()


# --- Interfaccia ---------------------------------------------------------------

func _build_ui() -> void:
	# Fase 8: tema dell'interfaccia (pergamene dell'originale, caratteri OFL). I controlli sotto un CanvasLayer non ereditano
	# il tema della finestra: si fonde nel tema predefinito, che vale ovunque (anche per menu a tendina e suggerimenti).
	UiTheme.install()
	# Luoghi leggendari: sotto le pedine (pallini discreti, medaglione al passaggio del mouse)
	_site_layer = SiteLayer.new()
	_site_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_site_layer)
	# Segnalini sotto a tutto il resto dell'interfaccia.
	_army_layer = ArmyLayerScript.new()
	_army_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_army_layer)
	# luoghi in evidenza (mouse, scheda aperta) sopra le pedine (28/11/2026)
	_ui.add_child(_site_layer.make_overlay())

	_message = Label.new()
	_message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_message.offset_left = 48
	_message.offset_top = 48
	_message.add_theme_font_size_override("font_size", 22)
	_message.theme_type_variation = "MapLabel"
	_message.visible = false
	_ui.add_child(_message)

	_build_top_bar()
	_build_hud()
	_build_warning_panel()
	_build_info_panel()
	_build_army_panel()
	_build_events_panel()
	_build_court_panel()
	_build_agent_panel()
	_build_diplomacy_panel()
	_build_standings_panel()
	_build_religion_legend()
	_build_mission_menu()
	_build_history_panel()
	_build_proposal_panel()
	_build_prisoner_panel()
	_build_site_choice_panel()
	_build_end_panel()
	_build_unit_info_panel()
	_build_province_modal()
	_saves_panel = SaveLoadPanel.new()
	_saves_panel.save_requested.connect(_save_named)
	_saves_panel.load_requested.connect(_on_load_chosen)
	_ui.add_child(_saves_panel)
	_stack_sheet(_saves_panel)

	_toast_holder = CenterContainer.new()
	_toast_holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast_holder.offset_top = TOP_BAR_HEIGHT + 8.0
	_toast_holder.offset_bottom = TOP_BAR_HEIGHT + 8.0
	_toast_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_holder.z_index = 15
	_ui.add_child(_toast_holder)
	_toast_box = PanelContainer.new()
	_toast_box.add_theme_stylebox_override("panel", UiTheme.toast_box())
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.visible = false
	_toast_holder.add_child(_toast_box)
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", UiTheme.INK)
	_toast.add_theme_font_size_override("font_size", 17)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_child(_toast)

	_build_map_options()

	_help_label = Label.new()
	_help_label.text = Lang.t("H: comandi e tasti")
	_help_label.anchor_left = 1.0
	_help_label.anchor_right = 1.0
	_help_label.anchor_top = 1.0
	_help_label.anchor_bottom = 1.0
	_help_label.offset_right = -16.0
	_help_label.offset_top = -34.0
	_help_label.offset_bottom = -10.0
	_help_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_help_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help_label.theme_type_variation = "MapLabel"
	_help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_label.visible = false   # richiesta di Federico del 27/11/2026: la scritta sta in piccolo sotto le carte della barra
	_ui.add_child(_help_label)

	_help_panel = PanelContainer.new()
	_help_panel.visible = false
	_help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_help_panel)
	_stack_sheet(_help_panel)
	var help_margin := _margin()
	_help_panel.add_child(help_margin)
	var help_box := VBoxContainer.new()
	help_box.add_theme_constant_override("separation", 6)
	help_margin.add_child(help_box)
	var help_head := HBoxContainer.new()
	help_box.add_child(help_head)
	var help_title := Label.new()
	help_title.text = Lang.t("Comandi e tasti")
	help_title.theme_type_variation = "Title"
	help_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_head.add_child(help_title)
	var help_close := _make_button(Lang.t("Chiudi (H o Esc)"))
	help_close.pressed.connect(func() -> void: _help_panel.visible = false)
	help_head.add_child(help_close)
	help_box.add_child(UiTheme.divider())
	# sezioni su due colonne: titolo nel carattere dei titoli, tasti in grassetto (CampaignUiHelp)
	var help_columns := HBoxContainer.new()
	help_columns.add_theme_constant_override("separation", 28)
	help_box.add_child(help_columns)
	var sections := CampaignUiHelp.sections()
	var columns: Array[VBoxContainer] = []
	for i in 2:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		col.custom_minimum_size = Vector2(HELP_COLUMN_WIDTH, 0)
		help_columns.add_child(col)
		columns.append(col)
	for i in sections.size():
		var section: Array = sections[i]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		columns[int(HELP_SECTION_COLUMNS[i]) if i < HELP_SECTION_COLUMNS.size() else 1].add_child(box)
		var head := Label.new()
		head.text = str(section[0])
		head.theme_type_variation = "Subtitle"
		box.add_child(head)
		var rows := RichTextLabel.new()
		rows.bbcode_enabled = true
		rows.fit_content = true
		rows.scroll_active = false
		rows.selection_enabled = false
		rows.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.custom_minimum_size = Vector2(HELP_COLUMN_WIDTH, 0)
		rows.add_theme_color_override("default_color", UiTheme.INK)
		rows.add_theme_font_size_override("normal_font_size", HELP_TEXT_SIZE)
		rows.add_theme_font_size_override("bold_font_size", HELP_TEXT_SIZE)
		rows.add_theme_font_override("bold_font", UiTheme.bold_font())
		rows.add_theme_constant_override("line_separation", 3)
		rows.text = CampaignUiHelp.bbcode(section[1])
		box.add_child(rows)

	_summary_panel = PanelContainer.new()
	_summary_panel.visible = false
	_summary_panel.position = Vector2(16, TOP_BAR_HEIGHT + 8.0)
	_ui.add_child(_summary_panel)
	var summary_margin := _margin()
	_summary_panel.add_child(summary_margin)
	var summary_label := Label.new()
	summary_label.name = "SummaryLabel"
	summary_margin.add_child(summary_label)


func _build_top_bar() -> void:
	_top_bar = PanelContainer.new()
	_top_bar.visible = false
	_top_bar.theme_type_variation = "TopBar"
	_top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_ui.add_child(_top_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_top_bar.add_child(row)
	_top_shield = UiTheme.shield("", Vector2(26, 30))
	row.add_child(_top_shield)

	_summary_button = _make_button(Lang.t("Riepilogo (F1)"))
	_summary_button.visible = false
	_summary_button.pressed.connect(_toggle_summary)
	row.add_child(_summary_button)

	_court_button = _make_button(Lang.t("Corte (C)"))
	_court_button.tooltip_text = Lang.t("Capo, erede, principi, principesse e generali della dinastia.")
	_court_button.pressed.connect(_toggle_court)
	row.add_child(_court_button)

	_diplomacy_button = _make_button(Lang.t("Diplomazia (D)"))
	_diplomacy_button.tooltip_text = Lang.t("Relazioni con le altre fazioni: guerra, alleanza, tregua, religione, influenza del capo.")
	_diplomacy_button.pressed.connect(_toggle_diplomacy)
	row.add_child(_diplomacy_button)

	_standings_button = _make_button(Lang.t("Classifica (G)"))
	_standings_button.tooltip_text = Lang.t("Le fazioni per province, reddito e quota, e quante province servono per il dominio.")
	_standings_button.pressed.connect(_toggle_standings)
	row.add_child(_standings_button)

	_year_label = Label.new()
	_year_label.theme_type_variation = "Subtitle"
	_year_label.add_theme_font_size_override("font_size", 18)
	row.add_child(_year_label)
	_treasury_label = Label.new()
	_treasury_label.add_theme_font_size_override("font_size", 18)
	row.add_child(_treasury_label)
	_income_label = Label.new()
	row.add_child(_income_label)
	_progress_label = Label.new()
	_progress_label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(_progress_label)
	_war_label = Label.new()
	_war_label.mouse_filter = Control.MOUSE_FILTER_STOP   # senza, il tooltip non compare
	row.add_child(_war_label)
	_papal_label = Label.new()
	_papal_label.visible = false
	_papal_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_papal_label.add_theme_color_override("font_color", BAD_COLOR)
	_papal_label.add_theme_font_size_override("font_size", 16)
	row.add_child(_papal_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var save_button := _make_button(Lang.t("Salva"))
	save_button.tooltip_text = Lang.t("Salva con un nome. F5: salvataggio rapido.")
	save_button.pressed.connect(_on_save_button)
	row.add_child(save_button)
	var load_button := _make_button(Lang.t("Carica"))
	load_button.tooltip_text = Lang.t("Scegli una partita salvata. F9: carica il salvataggio rapido.")
	load_button.pressed.connect(func() -> void: _saves_panel.open_load())
	row.add_child(load_button)
	var menu_button := _make_button(Lang.t("Menu"))
	menu_button.tooltip_text = Lang.t("Torna al menu iniziale (la partita non salvata si perde).")
	menu_button.pressed.connect(_on_menu_button)
	row.add_child(menu_button)
	_proposals_button = _make_button(Lang.t("Proposte"))
	_proposals_button.visible = false
	_proposals_button.pressed.connect(_on_proposals_button)
	row.add_child(_proposals_button)
	_end_year_button = _make_seal_button()
	if _end_year_button == null:
		_end_year_button = _make_button(Lang.t("Fine anno (Invio)"))
	else:
		var caption := Label.new()
		caption.text = Lang.t("Fine anno")
		caption.theme_type_variation = "Subtitle"
		caption.mouse_filter = Control.MOUSE_FILTER_STOP
		caption.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		caption.tooltip_text = Lang.t(END_YEAR_TOOLTIP) + Lang.t(" (Invio)")
		caption.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _end_year_button.disabled:
				_on_end_year())
		row.add_child(caption)
	_end_year_button.tooltip_text = Lang.t(END_YEAR_TOOLTIP)
	_end_year_button.pressed.connect(_on_end_year)
	row.add_child(_end_year_button)


## Fine anno con il sigillo di ceralacca dell'originale (richiesta di Federico): fotogramma 1 normale, 2 premuto; piu'
## chiaro al passaggio del mouse, grigio quando la partita e' finita. Null se l'immagine manca.
func _make_seal_button() -> TextureButton:
	if not AssetLibrary.is_available():
		return null
	var normal := AssetLibrary.texture(SEAL_IMAGE, 1)
	if normal == null:
		return null
	var pressed := AssetLibrary.texture(SEAL_IMAGE, 2)
	var b := TextureButton.new()
	b.texture_normal = normal
	b.texture_pressed = pressed if pressed != null else normal
	b.texture_hover = _tinted(normal, 1.25, false)
	b.texture_disabled = _tinted(normal, 1.0, true)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(SEAL_SIZE, SEAL_SIZE)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	b.focus_mode = Control.FOCUS_NONE   # Invio non deve premere i pulsanti (lo gestisce _unhandled_input)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


## Copia dell'immagine schiarita (`gain` > 1) o in scala di grigi.
static func _tinted(tex: Texture2D, gain: float, gray: bool) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	img = img.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if gray:
				var l := c.get_luminance() * 0.9
				img.set_pixel(x, y, Color(l, l, l, c.a * 0.7))
			else:
				img.set_pixel(x, y, Color(minf(c.r * gain, 1.0), minf(c.g * gain, 1.0), minf(c.b * gain, 1.0), c.a))
	return ImageTexture.create_from_image(img)


## Avviso del Papa (fase 5c): striscia rossa centrata sotto la barra, visibile solo con un avvertimento in corso.
func _build_warning_panel() -> void:
	_warning_panel = PanelContainer.new()
	_warning_panel.visible = false
	_warning_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_warning_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_warning_panel.offset_top = TOP_BAR_HEIGHT + 44.0
	_warning_panel.offset_bottom = TOP_BAR_HEIGHT + 44.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.45, 0.06, 0.05, 0.92)
	style.border_color = Color(1.0, 0.88, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.anti_aliasing = true
	style.set_content_margin_all(8.0)
	_warning_panel.add_theme_stylebox_override("panel", style)
	_ui.add_child(_warning_panel)
	_warning_label = Label.new()
	_warning_label.theme_type_variation = "MapLabel"
	_warning_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_warning_label.add_theme_font_size_override("font_size", 17)
	_warning_panel.add_child(_warning_label)


func _build_info_panel() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.visible = false
	_info_panel.anchor_left = 1.0
	_info_panel.anchor_right = 1.0
	_info_panel.anchor_top = 0.0
	_info_panel.anchor_bottom = 1.0
	_info_panel.offset_left = -PANEL_WIDTH - 16.0
	_info_panel.offset_right = -16.0
	_info_panel.offset_top = TOP_BAR_HEIGHT + 8.0
	_info_panel.offset_bottom = -44.0
	_info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(_info_panel)
	var info_margin := _margin()
	_info_panel.add_child(info_margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_margin.add_child(scroll)
	_info_box = VBoxContainer.new()
	_info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_info_box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_info_box.add_child(header)
	_province_shield = UiTheme.shield("")
	header.add_child(_province_shield)
	_province_title = Label.new()
	_province_title.theme_type_variation = "Title"
	_province_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_province_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_province_title)
	var province_close := _make_button(Lang.t("Chiudi"))
	province_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	province_close.tooltip_text = Lang.t("Chiude il pannello della provincia (Esc, dopo aver chiuso gli altri pannelli).")
	province_close.pressed.connect(func() -> void: _select(null))
	header.add_child(province_close)
	_province_tab_box = HBoxContainer.new()
	_province_tab_box.add_theme_constant_override("separation", 4)
	_province_tab_box.visible = false
	_info_box.add_child(_province_tab_box)
	_info_box.add_child(UiTheme.divider())
	_info_label = Label.new()
	_info_label.custom_minimum_size = Vector2(PANEL_WIDTH - 70.0, 0)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(_info_label)
	_province_box = VBoxContainer.new()
	_province_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_box.add_child(_province_box)


func _build_army_panel() -> void:
	_army_panel = PanelContainer.new()
	_army_panel.visible = false
	_army_panel.anchor_top = 1.0
	_army_panel.anchor_bottom = 1.0
	_army_panel.offset_left = 16.0
	_army_panel.offset_top = -44.0
	_army_panel.offset_bottom = -44.0
	_army_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(_army_panel)
	var margin := _margin()
	_army_panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var army_header := HBoxContainer.new()
	army_header.add_theme_constant_override("separation", 10)
	box.add_child(army_header)
	_army_shield = UiTheme.shield("")
	army_header.add_child(_army_shield)
	_army_label = Label.new()
	_army_label.custom_minimum_size = Vector2(300.0, 0.0)
	_army_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_army_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	army_header.add_child(_army_label)
	var army_close := _make_button(Lang.t("Chiudi (Esc)"))
	army_close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	army_close.tooltip_text = Lang.t("Chiude il pannello e toglie la selezione dell'esercito.")
	army_close.pressed.connect(_close_piece_panel)
	army_header.add_child(army_close)
	# Fase 8: le pile come carte dell'originale, con gli uomini sotto (dettagli nel suggerimento).
	_army_cards = HFlowContainer.new()
	_army_cards.add_theme_constant_override("h_separation", 4)
	_army_cards.add_theme_constant_override("v_separation", 4)
	_army_cards.custom_minimum_size = Vector2(8.0 * (CARD_SIZE.x + 12.0), 0.0)
	box.add_child(_army_cards)
	_army_commander_label = Label.new()
	_army_commander_label.custom_minimum_size = Vector2(300.0, 0.0)
	_army_commander_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_army_commander_label.visible = false
	box.add_child(_army_commander_label)
	_army_attr_box = VBoxContainer.new()
	box.add_child(_army_attr_box)
	_army_commander_row = HBoxContainer.new()
	_army_commander_row.visible = false
	box.add_child(_army_commander_row)
	_army_commander_select = OptionButton.new()
	_army_commander_select.focus_mode = Control.FOCUS_NONE
	_army_commander_select.fit_to_longest_item = false
	_army_commander_select.clip_text = true
	_army_commander_select.custom_minimum_size = Vector2(300.0, 0.0)
	_army_commander_select.tooltip_text = Lang.t("Mette al comando un personaggio presente nella stessa regione.")
	_army_commander_select.item_selected.connect(_on_commander_chosen.bind(_army_commander_select))
	_army_commander_row.add_child(_army_commander_select)
	var row := HBoxContainer.new()
	box.add_child(row)
	_army_cancel_button = _make_button(Lang.t("Annulla movimento"))
	_army_cancel_button.pressed.connect(_on_cancel_move_pressed)
	row.add_child(_army_cancel_button)
	_army_assault_button = _make_button(Lang.t("Assalta il castello"))
	_army_assault_button.visible = false
	_army_assault_button.pressed.connect(_on_assault_pressed)
	row.add_child(_army_assault_button)
	_army_castle_button = _make_button(Lang.t("Barricati nel castello"))
	_army_castle_button.visible = false
	_army_castle_button.pressed.connect(_on_castle_pressed)
	row.add_child(_army_castle_button)
	_army_target_button = _make_button(Lang.t("Scegli il bersaglio"))
	_army_target_button.visible = false
	_army_target_button.pressed.connect(_on_target_button_pressed)
	row.add_child(_army_target_button)
	var hint := Label.new()
	hint.text = Lang.t("  Trascina o clic destro: su una regione = muovi o attacca; su un tuo esercito = unisci")
	row.add_child(hint)
	# Dividere e unire (manuale p30): caselle sulle pile, poi Dividi / Sposta in / Unisci tutto in.
	_army_stacks_box = VBoxContainer.new()
	_army_stacks_box.visible = false
	box.add_child(_army_stacks_box)
	_army_split_row = HBoxContainer.new()
	_army_split_row.visible = false
	box.add_child(_army_split_row)
	var split_button := _make_button(Lang.t("Dividi le pile scelte"))
	split_button.tooltip_text = Lang.t("Le pile spuntate formano un esercito nuovo nella stessa regione (riceve un comandante a fine anno).")
	split_button.pressed.connect(_on_split_pressed)
	_army_split_row.add_child(split_button)
	_army_partner_select = OptionButton.new()
	_army_partner_select.focus_mode = Control.FOCUS_NONE
	_army_partner_select.tooltip_text = Lang.t("Altro esercito della tua fazione nella stessa regione.")
	_army_split_row.add_child(_army_partner_select)
	var move_button := _make_button(Lang.t("Sposta le scelte"))
	move_button.tooltip_text = Lang.t("Sposta le pile spuntate nell'esercito scelto qui accanto.")
	move_button.pressed.connect(_on_transfer_pressed)
	_army_split_row.add_child(move_button)
	var merge_button := _make_button(Lang.t("Unisci tutto"))
	merge_button.tooltip_text = Lang.t("Unisce tutto questo esercito in quello scelto qui accanto (entro il massimo di pile per esercito).")
	merge_button.pressed.connect(_on_merge_pressed)
	_army_split_row.add_child(merge_button)
	# Riaddestramento: stesse caselle delle pile; costo totale nel testo, motivi e tesoro nel tooltip.
	_army_retrain_row = HBoxContainer.new()
	_army_retrain_row.visible = false
	box.add_child(_army_retrain_row)
	_army_retrain_button = _make_button(Lang.t(CampaignUiRetrain.BUTTON_TEXT))
	_army_retrain_button.pressed.connect(_on_retrain_pressed)
	_army_retrain_row.add_child(_army_retrain_button)
	_army_retrain_cancel_button = _make_button(Lang.t(CampaignUiRetrain.CANCEL_TEXT))
	_army_retrain_cancel_button.visible = false
	_army_retrain_cancel_button.pressed.connect(_on_retrain_cancel_pressed)
	_army_retrain_row.add_child(_army_retrain_cancel_button)
	# Congedo (ADR-031): stesse caselle; chiede conferma.
	_army_dismiss_row = HBoxContainer.new()
	_army_dismiss_row.visible = false
	box.add_child(_army_dismiss_row)
	_army_dismiss_button = _make_button(Lang.t("Congeda le unità scelte"))
	_army_dismiss_button.pressed.connect(func() -> void: _ask_dismiss(_selected_army, _checked_stacks()))
	_army_dismiss_row.add_child(_army_dismiss_button)


## Pannello dell'agente selezionato (in basso a sinistra, al posto di quello dell'esercito).
func _build_agent_panel() -> void:
	_agent_panel = PanelContainer.new()
	_agent_panel.visible = false
	_agent_panel.anchor_top = 1.0
	_agent_panel.anchor_bottom = 1.0
	_agent_panel.offset_left = 16.0
	_agent_panel.offset_top = -44.0
	_agent_panel.offset_bottom = -44.0
	_agent_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(_agent_panel)
	var margin := _margin()
	_agent_panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var agent_header := HBoxContainer.new()
	agent_header.add_theme_constant_override("separation", 10)
	box.add_child(agent_header)
	_agent_label = Label.new()
	_agent_label.custom_minimum_size = Vector2(340.0, 0.0)
	_agent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_agent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agent_header.add_child(_agent_label)
	var agent_close := _make_button(Lang.t("Chiudi (Esc)"))
	agent_close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	agent_close.tooltip_text = Lang.t("Chiude il pannello e toglie la selezione dell'agente.")
	agent_close.pressed.connect(_close_piece_panel)
	agent_header.add_child(agent_close)
	var row := HBoxContainer.new()
	box.add_child(row)
	_agent_cancel_move_button = _make_button(Lang.t("Annulla movimento"))
	_agent_cancel_move_button.pressed.connect(_on_agent_cancel_move_pressed)
	row.add_child(_agent_cancel_move_button)
	_agent_cancel_mission_button = _make_button(Lang.t("Annulla missione"))
	_agent_cancel_mission_button.pressed.connect(_on_agent_cancel_mission_pressed)
	row.add_child(_agent_cancel_mission_button)
	_agent_hint = Label.new()
	_agent_hint.text = Lang.t("Trascina o clic destro: su una regione = muovi; su un re, un esercito o un agente = proposte e missioni")
	_agent_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_agent_hint.custom_minimum_size = Vector2(340.0, 0.0)
	box.add_child(_agent_hint)


## Menu delle azioni dell'agente (riempito da _show_mission_menu); sta sopra gli altri pannelli.
func _build_mission_menu() -> void:
	_mission_menu = PanelContainer.new()
	_mission_menu.visible = false
	_mission_menu.z_index = 10
	_ui.add_child(_mission_menu)
	_stack_sheet(_mission_menu, null, 10)
	var margin := _margin()
	_mission_menu.add_child(margin)
	_mission_menu_box = VBoxContainer.new()
	margin.add_child(_mission_menu_box)


func _build_diplomacy_panel() -> void:
	_diplomacy_panel = PanelContainer.new()
	_diplomacy_panel.visible = false
	_diplomacy_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_diplomacy_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_diplomacy_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_diplomacy_panel)
	_stack_sheet(_diplomacy_panel)
	var margin := _margin()
	_diplomacy_panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var diplomacy_header := HBoxContainer.new()
	diplomacy_header.add_theme_constant_override("separation", 10)
	box.add_child(diplomacy_header)
	_diplomacy_shield = UiTheme.shield("")
	diplomacy_header.add_child(_diplomacy_shield)
	_diplomacy_title = Label.new()
	_diplomacy_title.theme_type_variation = "Title"
	diplomacy_header.add_child(_diplomacy_title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(760.0, 420.0)
	box.add_child(scroll)
	_diplomacy_box = VBoxContainer.new()
	_diplomacy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_diplomacy_box)
	var close_button := _make_button(Lang.t("Chiudi (Esc)"))
	close_button.pressed.connect(_toggle_diplomacy)
	box.add_child(close_button)


## Legenda della tinta religiosa (a sinistra, a metà altezza), visibile solo con la tinta religiosa (tasto R).
func _build_religion_legend() -> void:
	_legend_panel = PanelContainer.new()
	_legend_panel.visible = false
	_legend_panel.anchor_top = 0.5
	_legend_panel.anchor_bottom = 0.5
	_legend_panel.offset_left = 16.0
	_legend_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_legend_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_legend_panel)
	var margin := _margin()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	var title := Label.new()
	title.text = Lang.t("Religione maggioritaria (R)")
	title.add_theme_color_override("font_color", SECTION_COLOR)
	box.add_child(title)
	for entry in CampaignUiReligion.legend_entries():
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch := ColorRect.new()
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch_color: Color = entry["colore"]
		swatch.color = swatch_color
		swatch.custom_minimum_size = Vector2(14.0, 14.0)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var name_label := Label.new()
		name_label.text = " " + str(entry["nome"])
		row.add_child(name_label)
		box.add_child(row)


func _build_events_panel() -> void:
	_events_panel = PanelContainer.new()
	_events_panel.visible = false
	_events_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_events_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_events_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_events_panel)
	_stack_sheet(_events_panel)
	var margin := _margin()
	_events_panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	box.add_theme_constant_override("separation", 6)
	_events_title = Label.new()
	_events_title.theme_type_variation = "Title"
	_events_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_events_title)
	_events_subtitle = Label.new()
	_events_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_events_subtitle.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	_events_subtitle.add_theme_font_size_override("font_size", 15)
	box.add_child(_events_subtitle)
	box.add_child(UiTheme.divider())
	# schede: «Messaggi» (resoconto dell'anno) e «Agenti» (elenco con «Raggiungi», richiesta di Federico del 18/11/2026)
	_events_tabs = TabContainer.new()
	_events_tabs.tab_changed.connect(func(_i: int) -> void:
		_refresh_agents_tab()
		_fit_events_panel())
	box.add_child(_events_tabs)
	_events_scroll = ScrollContainer.new()
	_events_scroll.name = Lang.t("Messaggi")
	_events_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_events_scroll.custom_minimum_size = Vector2(EVENTS_WIDTH + 20.0, EVENTS_MIN_HEIGHT)
	_events_tabs.add_child(_events_scroll)
	_agents_scroll = ScrollContainer.new()
	_agents_scroll.name = Lang.t("Agenti")
	_agents_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_agents_scroll.custom_minimum_size = Vector2(EVENTS_WIDTH + 20.0, EVENTS_MIN_HEIGHT)
	_events_tabs.add_child(_agents_scroll)
	_agents_list = VBoxContainer.new()
	_agents_list.add_theme_constant_override("separation", 6)
	_agents_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_agents_scroll.add_child(_agents_list)
	_events_label = RichTextLabel.new()
	_events_label.bbcode_enabled = true
	_events_label.fit_content = true
	_events_label.scroll_active = false
	_events_label.selection_enabled = false
	_events_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_events_label.custom_minimum_size = Vector2(EVENTS_WIDTH, 0.0)
	_events_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_events_label.add_theme_color_override("default_color", UiTheme.INK)
	_events_label.add_theme_font_size_override("normal_font_size", UiTheme.TEXT_SIZE)
	_events_label.add_theme_font_size_override("bold_font_size", UiTheme.TEXT_SIZE)
	_events_label.add_theme_font_size_override("italics_font_size", UiTheme.TEXT_SIZE)
	var bold := UiTheme.bold_font()
	if bold != null:
		_events_label.add_theme_font_override("bold_font", bold)
	var italic := UiTheme.italic_font()
	if italic != null:
		_events_label.add_theme_font_override("italics_font", italic)
	_events_label.add_theme_constant_override("table_v_separation", 0)
	_events_label.add_theme_constant_override("line_separation", 2)
	_events_scroll.add_child(_events_label)
	box.add_child(UiTheme.divider())
	var close_button := _make_button(Lang.t("Chiudi (Esc)"))
	close_button.pressed.connect(_hide_events)
	box.add_child(close_button)


func _build_court_panel() -> void:
	_court_panel = PanelContainer.new()
	_court_panel.visible = false
	_court_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_court_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_court_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_court_panel)
	_stack_sheet(_court_panel)
	var margin := _margin()
	_court_panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var court_header := HBoxContainer.new()
	court_header.add_theme_constant_override("separation", 10)
	box.add_child(court_header)
	_court_shield = UiTheme.shield("")
	court_header.add_child(_court_shield)
	_court_title = Label.new()
	_court_title.theme_type_variation = "Title"
	court_header.add_child(_court_title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(1060.0, 620.0)   # piu' larga per la sala del consiglio (20/11/2026)
	box.add_child(scroll)
	_court_box = VBoxContainer.new()
	_court_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_court_box)
	var close_button := _make_button(Lang.t("Chiudi (Esc)"))
	close_button.pressed.connect(_toggle_court)
	box.add_child(close_button)


# --- Pannello della corte ----------------------------------------------------------

func _toggle_court() -> void:
	if _state == null or not _ready_to_navigate:
		return
	_court_panel.visible = not _court_panel.visible
	GameAudio.play_sfx("pergamena" if _court_panel.visible else "chiudi")
	if _court_panel.visible:
		_diplomacy_panel.visible = false
		_standings_panel.visible = false
	_refresh_court_panel()


# --- Classifica, eventi storici e fine partita (fasi 6a e 6b) -----------------------------------

func _build_standings_panel() -> void:
	_standings_panel = PanelContainer.new()
	_standings_panel.visible = false
	_standings_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_standings_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_standings_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_standings_panel)
	_stack_sheet(_standings_panel)
	var margin := _margin()
	_standings_panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	_standings_title = Label.new()
	_standings_title.add_theme_font_size_override("font_size", 18)
	_standings_title.add_theme_color_override("font_color", SECTION_COLOR)
	box.add_child(_standings_title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(560.0, 380.0)
	box.add_child(scroll)
	_standings_box = VBoxContainer.new()
	_standings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_standings_box)
	var close_button := _make_button(Lang.t("Chiudi (Esc)"))
	close_button.pressed.connect(_toggle_standings)
	box.add_child(close_button)


func _toggle_standings() -> void:
	if _state == null or not _ready_to_navigate:
		return
	_standings_panel.visible = not _standings_panel.visible
	if _standings_panel.visible:
		_court_panel.visible = false
		_diplomacy_panel.visible = false
		_hide_mission_menu()
	_refresh_standings_panel()


## Ricostruisce il pannello della classifica dallo stato attuale (solo se è aperto): una riga per fazione viva con province
## (CampaignUiVictory.standings_rows), il giocatore evidenziato.
func _refresh_standings_panel() -> void:
	if _standings_panel == null or not _standings_panel.visible or _state == null:
		return
	_clear_children(_standings_box)
	_standings_title.text = CampaignUiVictory.standings_title(_state)
	_standings_box.add_child(_standings_grid(CampaignUiVictory.standings_rows(_state)))


## Tabella della classifica (intestazioni e righe con il colore della fazione); il giocatore in evidenza.
func _standings_grid(rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	for header in CampaignUiVictory.standings_headers():
		var head := Label.new()
		head.text = header
		head.add_theme_color_override("font_color", SECTION_COLOR)
		grid.add_child(head)
	for item in rows:
		var row: Dictionary = item
		var cells: PackedStringArray = row["celle"]
		var mine := bool(row["giocatore"])
		for c in range(cells.size()):
			if c == 1:
				var first := HBoxContainer.new()
				var swatch := ColorRect.new()
				swatch.color = StateTint.owner_color(_region_map, str(row["fazione"]))
				swatch.custom_minimum_size = Vector2(14.0, 14.0)
				swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				first.add_child(swatch)
				var faction_cell := Label.new()
				faction_cell.text = " " + cells[c]
				if mine:
					faction_cell.add_theme_color_override("font_color", SECTION_COLOR)
				first.add_child(faction_cell)
				grid.add_child(first)
			else:
				var cell := Label.new()
				cell.text = cells[c]
				if mine:
					cell.add_theme_color_override("font_color", SECTION_COLOR)
				grid.add_child(cell)
	return grid


## Finestra illustrata degli eventi (storici, avvisi degli eventi importanti, notizie): IllustratedModal con l'immagine come
## sfondo (EventArt.window_texture), categoria e titolo in alto, testo ed effetto sulla piastra di pergamena, «Salta tutte» e
## «Avanti». Richiesta di Federico del 2026-11-20. Gli avvisi con un luogo portano la mappa li' (_focus_alert).
func _build_history_panel() -> void:
	_history_panel = IllustratedModal.new()
	_history_panel.visible = false
	_history_panel.z_index = 5
	_ui.add_child(_history_panel)
	_stack_sheet(_history_panel)
	_history_scroll = ScrollContainer.new()
	_history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_history_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_panel.body.add_child(_history_scroll)
	_history_text = Label.new()
	_history_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_text.custom_minimum_size = Vector2(240.0, 0.0)
	_history_scroll.add_child(_history_text)
	_history_effect = Label.new()
	_history_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history_effect.custom_minimum_size = Vector2(240.0, 0.0)
	_history_effect.add_theme_color_override("font_color", UiTheme.INK_BLUE)
	_history_panel.body.add_child(_history_effect)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	_history_panel.body.add_child(row)
	_history_skip = _make_button(Lang.t("Salta tutte"))
	_history_skip.pressed.connect(_on_history_skip)
	row.add_child(_history_skip)
	_history_button = _make_button(Lang.t("Chiudi"))
	_history_button.pressed.connect(_on_history_close)
	row.add_child(_history_button)
	_alert_marker = AlertMarker.new()
	_alert_marker.visible = false
	_alert_marker.z_index = 4
	_ui.add_child(_alert_marker)


## Mostra la prossima finestra illustrata; finite quelle, il resoconto dell'anno, poi prigionieri, proposte e fine partita.
func _show_next_popup() -> void:
	if not _history_queue.is_empty():
		var window: Dictionary = _history_queue.pop_front()
		_show_illustrated(window)
		GameAudio.play_sfx("evento_islamico" if _is_islamic_player() else "evento_cristiano")
		return
	_end_alerts()
	# una finestra alla volta: ognuna, chiudendosi, richiama questa funzione per la successiva
	if _show_next_prisoners() or _show_next_site_choice() or _show_next_proposal():
		return
	if not _report_pending.is_empty():
		var r := _report_pending
		_report_pending = {}
		var secs: Array[Dictionary] = []
		secs.assign(r["sezioni"])
		_show_events(int(r["anno"]), secs, str(r["fine"]))
		if _end_pending:
			return   # la fine partita si apre alla chiusura del resoconto (_hide_events)
	if _end_pending:
		_end_pending = false
		_show_end_screen()


## Riempie la finestra illustrata con una finestra di CampaignUiEvents o di CampaignUiAlerts e la mette al suo posto.
func _show_illustrated(window: Dictionary) -> void:
	var alert := str(window.get("tema", "")) != "" or str(window.get("luogo_leggendario", "")) != ""
	var year := int(window.get("anno", _state.year if _state != null else 0))
	var category := str(window.get("categoria", ""))
	if category == "":
		category = Lang.t("Evento storico") if int(window.get("indice", -1)) >= 0 else Lang.t("Notizia")
	_history_panel.set_category("%s · %s" % [category, Lang.t("Anno del Signore %d") % year], str(window.get("esito", "")))
	_history_panel.set_title(str(window.get("titolo", "")))
	_history_panel.set_picture(EventArt.window_texture(window))
	_history_text.text = str(window.get("testo", ""))
	var effect := str(window.get("effetto", ""))
	if effect != "" and not alert:
		effect = Lang.t("Effetto: %s.") % effect
	_history_effect.text = effect
	_history_effect.visible = effect != ""
	var left := _history_queue.size()
	_history_button.text = Lang.t("Chiudi (Esc)") if left == 0 else Lang.t("Avanti (Esc): ancora %d") % left
	_history_skip.visible = left > 0
	_alert_place = str(window.get("luogo", ""))
	if not _anchors.has(_alert_place):
		_alert_place = ""
	_alert_marker.visible = false
	_history_panel.visible = true
	_place_history_panel()


## Misura e posizione della finestra illustrata: con un luogo sta a destra e la mappa porta il luogo al centro dello spazio
## libero a sinistra; senza luogo sta al centro dello spazio sopra la barra.
func _place_history_panel() -> void:
	var view := get_viewport().get_visible_rect().size
	var free := view.y - (_hud.bar_height() if _hud != null else 0.0)
	var width := clampf(view.x * HISTORY_WIDTH_SHARE, minf(HISTORY_MIN_WIDTH, view.x - 40.0), minf(HISTORY_MAX_WIDTH, view.x - 40.0))
	_history_panel.set_width(width)
	# altezza del testo misurata col carattere alla larghezza della piastra (la Label a capo automatico non la conosce
	# finche' la finestra non e' stata impaginata almeno una volta)
	var font := _history_text.get_theme_font("font")
	var font_size := _history_text.get_theme_font_size("font_size")
	var text_width := maxf(120.0, width - HISTORY_TEXT_INSET)
	var text_height := font.get_multiline_string_size(_history_text.text, HORIZONTAL_ALIGNMENT_LEFT, text_width, font_size).y + 4.0
	_history_scroll.custom_minimum_size.y = clampf(text_height, 24.0, maxf(80.0, free * HISTORY_TEXT_SHARE))
	# due fotogrammi: al primo le Label a capo automatico prendono la loro larghezza, al secondo l'altezza giusta
	for i in 2:
		await get_tree().process_frame
		if not _history_panel.visible:
			return
		_history_panel.reset_size()
	var panel_size := _history_panel.get_combined_minimum_size()
	_history_panel.size = panel_size
	var y := roundf(maxf(12.0, (free - panel_size.y) * 0.5))
	if _alert_place != "":
		_history_panel.position = Vector2(roundf(view.x - panel_size.x - 28.0), y)
		_focus_alert(_alert_place)
	else:
		_history_panel.position = Vector2(roundf((view.x - panel_size.x) * 0.5), y)


## Porta la mappa sul luogo dell'avviso con uno spostamento animato: il luogo va al centro dello spazio libero a sinistra
## della finestra, con uno zoom tra quello minimo dell'avviso e ALERT_MAX_ZOOM; il segnale pulsante lo indica.
func _focus_alert(place: String) -> void:
	if not _anchors.has(place):
		return
	if _alert_return.is_empty():
		_alert_return = {"pos": _camera.position, "zoom": _zoom}
	var view := get_viewport().get_visible_rect().size
	var free := view.y - (_hud.bar_height() if _hud != null else 0.0)
	var low := ALERT_WORLD_ZOOM if RegionMap.world else _min_zoom * ALERT_EUROPE_ZOOM
	var new_zoom := clampf(clampf(_zoom, minf(low, ALERT_MAX_ZOOM), ALERT_MAX_ZOOM), _min_zoom, MAX_ZOOM)
	var spot := Vector2(maxf(140.0, _history_panel.position.x * 0.5), free * 0.5)
	var anchor: Vector2 = _anchors[place]
	var target := anchor - (_projection.screen_to_flat(spot) - _view_size() / 2.0) / new_zoom
	_pan_to(target, new_zoom)
	_alert_marker.visible = true
	_alert_marker.position = _world_to_screen(anchor).round()


## Spostamento animato della camera (e dello zoom) verso `target`.
func _pan_to(target: Vector2, new_zoom: float) -> void:
	if _alert_tween != null and _alert_tween.is_valid():
		_alert_tween.kill()
	_alert_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_alert_tween.tween_method(_pan_step.bind(_camera.position, target, _zoom, new_zoom), 0.0, 1.0, ALERT_PAN_SECONDS)
	_alert_tween.tween_callback(_pan_done)


func _pan_step(t: float, from_pos: Vector2, to_pos: Vector2, from_zoom: float, to_zoom: float) -> void:
	_zoom = lerpf(from_zoom, to_zoom, t)
	_camera.zoom = Vector2(_zoom, _zoom)
	_camera.position = from_pos.lerp(to_pos, t)
	_clamp_camera()


## Fine dello spostamento: confini e pedine allo zoom nuovo.
func _pan_done() -> void:
	_border_layer.set_zoom(_zoom)
	if _markers_zoom > 0.0 and absf(log(_zoom / _markers_zoom)) > 0.22:
		_rebuild_markers()


func _on_viewport_resized_alerts() -> void:
	if _history_panel != null and _history_panel.visible:
		_place_history_panel()


## Chiude gli avvisi: toglie il segnale e riporta la mappa dov'era prima del primo avviso.
func _end_alerts() -> void:
	_alert_place = ""
	if _alert_marker != null:
		_alert_marker.visible = false
	if not _alert_return.is_empty():
		var back := _alert_return
		_alert_return = {}
		_pan_to(back["pos"], float(back["zoom"]))
	elif _alert_tween != null and _alert_tween.is_valid():
		_alert_tween.kill()


## Punto dello schermo di un punto della mappa (l'inverso di _screen_to_world, prospettiva compresa).
func _world_to_screen(world: Vector2) -> Vector2:
	return _projection.flat_to_screen((world - _camera.position) * _zoom + _view_size() / 2.0)


func _on_history_close() -> void:
	_history_panel.visible = false
	_show_next_popup()


## «Salta tutte»: chiude le finestre illustrate rimaste e passa al resoconto.
func _on_history_skip() -> void:
	_history_queue.clear()
	_on_history_close()


## Immagine e categoria di una finestra di prigionieri o proposte (IllustratedModal).
func _illustrate(panel: PanelContainer, category: String, theme: String, seed: String) -> void:
	var modal := panel as IllustratedModal
	if modal == null:
		return
	modal.set_category(category)
	modal.set_picture(EventArt.theme_texture(theme, seed))


## Finestra dei prigionieri (ADR-073): come vincitore Libera, Chiedi il riscatto o Giustizia tutti; come sconfitto a cui
## si chiede il riscatto Paga o Rifiuta. Non si chiude senza scegliere.
func _build_prisoner_panel() -> void:
	var modal := IllustratedModal.new()
	modal.set_width(640.0)
	_prisoner_panel = modal
	_prisoner_panel.visible = false
	_prisoner_panel.z_index = 6
	_prisoner_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prisoner_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prisoner_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_prisoner_panel)
	_stack_sheet(_prisoner_panel)
	var box := modal.body
	_prisoner_title = Label.new()
	_prisoner_title.add_theme_font_size_override("font_size", 20)
	_prisoner_title.add_theme_color_override("font_color", SECTION_COLOR)
	_prisoner_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prisoner_title.custom_minimum_size = Vector2(520.0, 0.0)
	box.add_child(_prisoner_title)
	_prisoner_text = Label.new()
	_prisoner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prisoner_text.custom_minimum_size = Vector2(520.0, 0.0)
	box.add_child(_prisoner_text)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_prisoner_buttons.clear()
	for i in 3:
		var b := _make_button("")
		b.pressed.connect(_on_prisoner_choice.bind(i))
		buttons.add_child(b)
		_prisoner_buttons.append(b)


## Mostra la prossima decisione sui prigionieri ancora in attesa; falso se non ce ne sono.
func _show_next_prisoners() -> bool:
	_prisoner_current = 0
	while not _prisoner_queue.is_empty():
		var prisoner_id: int = _prisoner_queue.pop_front()
		var w := CampaignUiPrisoners.window_of(_state, _player_id, prisoner_id)
		if w.is_empty():
			continue
		_prisoner_current = prisoner_id
		_prisoner_title.text = str(w["titolo"])
		_prisoner_text.text = str(w["testo"])
		_prisoner_choices.clear()
		var choices: Array = w["scelte"]
		for i in _prisoner_buttons.size():
			var b := _prisoner_buttons[i]
			b.visible = i < choices.size()
			if i < choices.size():
				b.text = str((choices[i] as Dictionary)["testo"])
				_prisoner_choices.append(str((choices[i] as Dictionary)["id"]))
		_illustrate(_prisoner_panel, Lang.t("Prigionieri"), "prigionia", str(prisoner_id))
		_prisoner_panel.visible = true
		return true
	_prisoner_panel.visible = false
	return false


func _on_prisoner_choice(index: int) -> void:
	if _prisoner_current == 0 or index >= _prisoner_choices.size():
		return
	var result := CampaignUiPrisoners.answer(_state, _player_id, _prisoner_current, _prisoner_choices[index])
	if str(result["testo"]) != "":
		_toast_show(str(result["testo"]))
	_prisoner_current = 0
	_prisoner_panel.visible = false
	_refresh_all()
	_show_next_popup()


## Finestra delle proposte dell'IA (fase 7b): chi propone, che cosa, entro quando; Accetta, Rifiuta o Decidi dopo.
func _build_proposal_panel() -> void:
	var modal := IllustratedModal.new()
	modal.set_width(620.0)
	_proposal_panel = modal
	_proposal_panel.visible = false
	_proposal_panel.z_index = 6
	_proposal_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_proposal_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_proposal_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_proposal_panel)
	_stack_sheet(_proposal_panel)
	var box := modal.body
	_proposal_title = Label.new()
	_proposal_title.add_theme_font_size_override("font_size", 20)
	_proposal_title.add_theme_color_override("font_color", SECTION_COLOR)
	_proposal_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_proposal_title.custom_minimum_size = Vector2(480.0, 0.0)
	box.add_child(_proposal_title)
	_proposal_text = Label.new()
	_proposal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_proposal_text.custom_minimum_size = Vector2(480.0, 0.0)
	box.add_child(_proposal_text)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_proposal_accept = _make_button(Lang.t("Accetta"))
	_proposal_accept.pressed.connect(_on_proposal_answer.bind(true))
	buttons.add_child(_proposal_accept)
	_proposal_refuse = _make_button(Lang.t("Rifiuta"))
	_proposal_refuse.pressed.connect(_on_proposal_answer.bind(false))
	buttons.add_child(_proposal_refuse)
	_proposal_later = _make_button(Lang.t("Decidi dopo (Esc)"))
	_proposal_later.pressed.connect(_on_proposal_later)
	buttons.add_child(_proposal_later)


## Mostra la prossima proposta ancora in attesa della coda; falso se non ce ne sono.
func _show_next_proposal() -> bool:
	_proposal_current = 0
	while not _proposal_queue.is_empty():
		var proposal_id: int = _proposal_queue.pop_front()
		var found := _proposal_window(proposal_id)
		if found.is_empty():
			continue
		_proposal_current = proposal_id
		_proposal_title.text = Lang.t("%s (ancora %d)") % [str(found["titolo"]), _proposal_queue.size()] if not _proposal_queue.is_empty() else str(found["titolo"])
		_proposal_text.text = str(found["testo"])
		_proposal_accept.text = str(found["accetta"])
		_proposal_refuse.text = str(found["rifiuta"])
		_illustrate(_proposal_panel, Lang.t("Diplomazia"), str(found["tipo"]), str(proposal_id))
		_proposal_panel.visible = true
		_refresh_proposals_button()
		return true
	_proposal_panel.visible = false
	_refresh_proposals_button()
	return false


func _proposal_window(proposal_id: int) -> Dictionary:
	for w in CampaignUiProposals.windows(_state, _player_id):
		if int(w["id"]) == proposal_id:
			return w
	return {}


func _on_proposal_answer(accept: bool) -> void:
	if _proposal_current == 0:
		return
	var result := CampaignUiProposals.answer(_state, _player_id, _proposal_current, accept)
	_toast_show(str(result["testo"]))
	_proposal_current = 0
	_refresh_all()
	_show_next_popup()


## «Decidi dopo»: chiude la finestra e la coda; le proposte restano in attesa fino alla scadenza e si riaprono dalla barra.
func _on_proposal_later() -> void:
	_proposal_panel.visible = false
	_proposal_current = 0
	_proposal_queue.clear()
	_refresh_proposals_button()
	_show_next_popup()   # poi il resoconto dell'anno e l'eventuale fine partita


func _on_proposals_button() -> void:
	if _state == null or _proposal_panel.visible:
		return
	_proposal_queue = CampaignUiProposals.queue_ids(_state, _player_id)
	_show_next_proposal()


func _refresh_proposals_button() -> void:
	if _proposals_button == null or _state == null:
		return
	var n := CampaignUiProposals.count(_state, _player_id)
	if _hud != null:
		_hud.set_proposals(n)
	_proposals_button.visible = n > 0
	_proposals_button.text = Lang.t("Proposte (%d)") % n


## Finestra della provincia (fase 8d): scheda Costruzione (costruiti, coda, da costruire, a tessere) e scheda Arruolamento
## (coda, carte delle unita', degli agenti e delle navi). Clic sinistro mette in coda, clic destro su una carta apre la scheda.
func _build_province_modal() -> void:
	_province_modal = PanelContainer.new()
	_province_modal.visible = false
	_province_modal.z_index = 5
	_province_modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_province_modal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_province_modal.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_province_modal)
	_stack_sheet(_province_modal)
	var margin := _margin()
	_province_modal.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_province_modal_title = Label.new()
	_province_modal_title.theme_type_variation = "Title"
	_province_modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_province_modal_title)
	# scorrere le province restando sulla stessa scheda (richiesta di Federico, 2026-11-10)
	var prev := _make_button("◀")
	prev.tooltip_text = Lang.t("Provincia precedente (tasto ,; con Maiusc solo quelle con qualcosa in coda)")
	prev.pressed.connect(func() -> void: _cycle_province(-1))
	head.add_child(prev)
	var next := _make_button("▶")
	next.tooltip_text = Lang.t("Provincia successiva (tasto .; con Maiusc solo quelle con qualcosa in coda)")
	next.pressed.connect(func() -> void: _cycle_province(1))
	head.add_child(next)
	var all_queues := _make_button(Lang.t("Tutte le code (Q)"))
	all_queues.tooltip_text = Lang.t("Le code di costruzione e addestramento di tutte le tue province")
	all_queues.pressed.connect(_toggle_queues_panel)
	head.add_child(all_queues)
	var close := _make_button(Lang.t("Chiudi (Esc)"))
	close.pressed.connect(func() -> void: _province_modal.visible = false)
	head.add_child(close)
	# richiesta di Federico (2026-11-11): le stesse schede della pergamena della provincia, non le linguette di Godot
	_modal_tab_row = HBoxContainer.new()
	_modal_tab_row.add_theme_constant_override("separation", 2)
	box.add_child(_modal_tab_row)
	_province_tabs = TabContainer.new()
	_province_tabs.tabs_visible = false
	_province_tabs.custom_minimum_size = MODAL_SIZE
	box.add_child(_province_tabs)
	_modal_build_box = _modal_tab(Lang.t("Costruzione"))
	_modal_recruit_box = _modal_tab(Lang.t("Arruolamento"))
	_modal_merc_box = _modal_tab(Lang.t("Mercenari"))


## Elenco delle code di tutte le province proprie (tasto Q, richiesta di Federico del 2026-11-10): una riga per provincia
## con le icone delle voci in coda; il nome apre la finestra della provincia, le icone la scheda giusta.
func _build_queues_panel() -> void:
	_queues_panel = PanelContainer.new()
	_queues_panel.visible = false
	_queues_panel.z_index = 6
	_queues_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_queues_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_queues_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_queues_panel)
	_stack_sheet(_queues_panel)
	var margin := _margin()
	_queues_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = Lang.t("Code di produzione")
	title.theme_type_variation = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var busy := CheckBox.new()
	busy.text = Lang.t("Solo con qualcosa in coda")
	busy.button_pressed = _queues_busy_only
	busy.toggled.connect(func(on: bool) -> void:
		_queues_busy_only = on
		_refresh_queues_panel())
	head.add_child(busy)
	var close := _make_button(Lang.t("Chiudi (Q)"))
	close.pressed.connect(_toggle_queues_panel)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_queues_box = VBoxContainer.new()
	_queues_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queues_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_queues_box)


func _toggle_queues_panel() -> void:
	if _queues_panel == null:
		_build_queues_panel()
	_queues_panel.visible = not _queues_panel.visible
	if _queues_panel.visible:
		_province_modal.visible = false
		GameAudio.play_sfx("pergamena")
		_refresh_queues_panel()


func _refresh_queues_panel() -> void:
	if _queues_panel == null or not _queues_panel.visible:
		return
	_clear_children(_queues_box)
	var rows := CampaignUiQueues.rows(_state, _player_id, _queues_busy_only)
	if rows.is_empty():
		var none := Label.new()
		none.text = Lang.t("Nessuna provincia con qualcosa in coda.") if _queues_busy_only else Lang.t("Nessuna provincia.")
		_queues_box.add_child(none)
		return
	for row_info in rows:
		var row_data: Dictionary = row_info
		var region_id := str(row_data["provincia"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var name_button := _make_button(str(row_data["nome"]))
		name_button.custom_minimum_size = Vector2(150, 0)
		name_button.tooltip_text = Lang.t("Apre la finestra della provincia")
		name_button.pressed.connect(_open_queue_province.bind(region_id, 0))
		if _selected != null and _selected.id == region_id:
			name_button.modulate = Color(1.0, 0.9, 0.55)
		row.add_child(name_button)
		var voci: Array = row_data["voci"]
		if voci.is_empty():
			var idle := Label.new()
			idle.text = Lang.t("nulla in coda")
			idle.modulate = Color(1, 1, 1, 0.6)
			row.add_child(idle)
		for q in voci:
			var item := _queue_review_item(q, region_id)
			var building := str(q["tipo"]) == QueueItem.KIND_BUILDING
			var holder := Control.new()
			var size: Vector2 = item["misura"]
			holder.custom_minimum_size = size
			holder.tooltip_text = str(item["suggerimento"])
			holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var tex: Texture2D = item["immagine"]
			if tex != null:
				var pic := TextureRect.new()
				pic.texture = tex
				pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				holder.add_child(pic)
			var cap := Label.new()
			cap.text = str(item["didascalia"]) if tex != null else str(item["suggerimento"]).get_slice("\n", 0)
			cap.add_theme_font_size_override("font_size", 10)
			cap.add_theme_color_override("font_color", Color.WHITE)
			cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			cap.add_theme_constant_override("outline_size", 3)
			cap.position = Vector2(2, size.y - 14)
			cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(cap)
			holder.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
					_open_queue_province(region_id, 0 if building else 1))
			row.add_child(holder)
		if bool(row_data["ripete"]):
			var rep_label := Label.new()
			rep_label.text = "↻"
			rep_label.tooltip_text = Lang.t("Coda di reclutamento ripetuta")
			row.add_child(rep_label)
		_queues_box.add_child(row)


## Dall'elenco delle code: sceglie la provincia (camera sopra) e ne apre la finestra sulla scheda `tab`.
func _open_queue_province(region_id: String, tab: int) -> void:
	var region := _state.campaign.region(region_id)
	if region == null:
		return
	_selected_castle = ""
	_selected_army = 0
	_selected_agent = 0
	_province_details = false
	_select(region)
	if _anchors.has(region_id):
		_camera.position = _anchors[region_id]
		_clamp_camera()
	_queues_panel.visible = false   # la finestra della provincia ha ◀ ▶ e «Tutte le code (Q)» per tornare qui
	_open_province_modal(tab)


func _modal_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_province_tabs.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)
	return inner


func _open_province_modal(tab: int) -> void:
	if _selected == null or _state.province(_selected.id) == null:
		return
	_province_tabs.current_tab = tab
	# finestra grande ma sempre dentro lo schermo (sopra la barra in basso)
	var view := get_viewport().get_visible_rect().size
	_province_tabs.custom_minimum_size = Vector2(minf(MODAL_SIZE.x, view.x - 120.0), minf(MODAL_SIZE.y, view.y - 300.0))
	_refresh_province_modal()
	_province_modal.visible = true
	_recenter.call_deferred(_province_modal)
	GameAudio.play_sfx("pergamena")


func _refresh_province_modal() -> void:
	var province := _state.province(_selected.id) if _selected != null else null
	if province == null or province.owner != _player_id:
		_province_modal.visible = false
		return
	_province_modal_title.text = CampaignUiText.region_name(_state, province.id)
	_refresh_modal_tab_row()
	_clear_children(_modal_build_box)
	_clear_children(_modal_recruit_box)
	_clear_children(_modal_merc_box)
	_fill_build_tab(province)
	_fill_recruit_tab(province)
	_fill_merc_tab(province)
	_refresh_queues_panel()


func _modal_header(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Subtitle"
	box.add_child(l)


func _modal_flow(box: VBoxContainer) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(flow)
	return flow


## Tessera cliccabile: immagine (o nome se manca), didascalia breve sotto, dettagli nel suggerimento; spenta se non si puo'.
## Tessera della finestra della provincia: immagine, nome intero in grassetto che va a capo (richiesta di Federico,
## 2026-11-10: i nomi tagliati si leggevano male) e, dopo il primo a capo di `caption`, i dettagli (costo, anni, uomini).
## `bold_lead` (richiesta di Federico del 25/11/2026: gli uomini dell'unita' in grassetto) apre la riga dei dettagli in
## grassetto, seguito da « · » e dal resto della didascalia.
func _modal_tile(tex: Texture2D, size: Vector2, caption: String, tip: String, enabled: bool, bold_lead: String = "") -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = "Tile"
	b.tooltip_text = tip
	b.disabled = not enabled
	var width := maxf(size.x + 16.0, MODAL_TILE_WIDTH)
	b.custom_minimum_size = Vector2(width, size.y + 64.0)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 4.0
	col.offset_bottom = -4.0
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 1)
	b.add_child(col)
	if tex != null:
		var pic := UiTheme.picture(tex, size)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if not enabled:
			pic.modulate = Color(1, 1, 1, 0.45)
		col.add_child(pic)
	var name_text := caption.get_slice("\n", 0)
	var details := caption.substr(name_text.length() + 1) if caption.contains("\n") else ""
	var label := Label.new()
	label.text = name_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width - 8.0, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_constant_override("line_spacing", -3)
	var bold := UiTheme.bold_font()
	if bold != null:
		label.add_theme_font_override("font", bold)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not enabled:
		label.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	col.add_child(label)
	if details != "":
		var info := Label.new()
		info.text = details
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(width - 8.0, 0)
		info.add_theme_font_size_override("font_size", 11)
		info.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if bold_lead == "":
			col.add_child(info)
		else:
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 0)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var lead := Label.new()
			lead.text = bold_lead
			lead.add_theme_font_size_override("font_size", 11)
			lead.add_theme_color_override("font_color", UiTheme.INK if enabled else UiTheme.INK_FAINT)
			if bold != null:
				lead.add_theme_font_override("font", bold)
			lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(lead)
			info.text = " · " + details
			info.autowrap_mode = TextServer.AUTOWRAP_OFF
			info.custom_minimum_size = Vector2.ZERO
			row.add_child(info)
			col.add_child(row)
	return b


func _fill_build_tab(province: ProvinceState) -> void:
	var box := _modal_build_box
	var keys: Array = province.buildings.keys()
	keys.sort()
	_modal_header(box, Lang.t("Costruiti (%d)") % keys.size())
	var built := _modal_flow(box)
	for key in keys:
		var level := province.level_of(str(key))
		var name_text := CampaignUiText.building_name(_state, str(key), level)
		var tile := _modal_tile(_building_icon(str(key), level, province.id), MODAL_ICON_SIZE, _building_caption(str(key), level), Lang.t("%s\nClic: la scheda dell'edificio") % name_text, true)
		tile.pressed.connect(_show_building_info.bind(str(key), level))
		built.add_child(tile)
	box.add_child(UiTheme.divider())
	_modal_header(box, Lang.t("In costruzione (%d/%d)") % [province.building_queue.size(), _rules.max_building_queue])
	if province.building_queue.is_empty():
		var none := Label.new()
		none.text = Lang.t("Nessun edificio in coda.")
		box.add_child(none)
	# richiesta di Federico (2026-11-11): gli edifici scelti stanno qui con la loro icona, non in un elenco, e non compaiono
	# piu' tra quelli da costruire; un clic li toglie dalla coda e li riporta la'
	var queue_flow := _modal_flow(box)
	for q in CampaignUiQueues.building_tiles(province):
		var q_family := str(q["famiglia"])
		var q_level := int(q["livello"])
		var q_text := CampaignUiQueues.building_tile_text(q, CampaignUiText.building_name(_state, q_family, q_level))
		var q_tile := _modal_tile(_building_icon(q_family, q_level, province.id), MODAL_ICON_SIZE,
			"%s\n%s" % [_building_caption(q_family, q_level), str(q_text["didascalia"])], str(q_text["suggerimento"]), true)
		q_tile.pressed.connect(_on_cancel_queue.bind(GameCommands.QUEUE_BUILDING, int(q["indice"])))
		queue_flow.add_child(q_tile)
	box.add_child(UiTheme.divider())
	var entries := CampaignUiQueues.not_queued(_building_entries(province), province)
	_modal_header(box, Lang.t("Da costruire"))
	var flow := _modal_flow(box)
	for pass_index in range(2):
		var wanted_ok := pass_index == 0   # prima i possibili, poi gli altri spenti con il motivo
		for e in entries:
			if bool(e["ok"]) != wanted_ok:
				continue
			var caption := Lang.t("%s\n%d f · %d a") % [_building_caption(str(e["family"]), int(e["level"])), int(e["cost"]), int(e["years"])]
			var tex := _building_icon(str(e["family"]), int(e["level"]), province.id) if AssetLibrary.is_available() else null
			var tile := _modal_tile(tex, MODAL_ICON_SIZE, caption, str(e["tip"]) + Lang.t("\nClic destro: scheda dell'edificio"), wanted_ok)
			tile.pressed.connect(_on_queue_building.bind(str(e["family"])))
			tile.gui_input.connect(_on_building_tile_input.bind(str(e["family"]), int(e["level"])))
			flow.add_child(tile)


func _fill_recruit_tab(province: ProvinceState) -> void:
	var box := _modal_recruit_box
	_modal_header(box, Lang.t("In arruolamento (%d/%d)") % [province.unit_queue_load(), _rules.max_unit_queue])
	if province.unit_queue.is_empty() and not province.repeats_units():
		var none := Label.new()
		none.text = Lang.t("Nessuna unità in coda.")
		box.add_child(none)
	# richiesta di Federico (2026-11-11): come per gli edifici, le unita' in coda sono tessere con l'icona; clic = via dalla coda
	var queue_flow := _modal_flow(box)
	for q in CampaignUiQueues.unit_tiles(province):
		var q_unit := str(q["unita"])
		var q_name := CampaignUiPapacy.queue_label(_state, q_unit)
		var q_text := CampaignUiQueues.unit_tile_text(q, q_name)
		var q_tex := PieceArt.unit_card(_data, _player_id, q_unit) if AssetLibrary.is_available() else null
		var waiting := bool(q["attesa"])
		var q_tile := _modal_tile(q_tex, MODAL_CARD_SIZE, "%s\n%s" % [q_name, str(q_text["didascalia"])], str(q_text["suggerimento"]), not waiting)
		if not waiting:
			q_tile.pressed.connect(_on_cancel_queue.bind(GameCommands.QUEUE_UNIT, int(q["indice"])))
		queue_flow.add_child(q_tile)
	box.add_child(_repeat_toggle(province))
	# richiesta di Federico (2026-11-18): sotto «Ripeti la coda» tre schede per scegliere tra truppe, flotta e agenti
	var groups := CampaignUiQueues.recruit_groups(_unit_entries(province))
	var counts: Array[int] = []
	for g in groups:
		counts.append((g["voci"] as Array).size())
	if _recruit_group < 0 or _recruit_group >= groups.size() or counts[_recruit_group] == 0:
		_recruit_group = maxi(0, counts.find(counts.max())) if counts.max() > 0 else 0
		for i in counts.size():
			if counts[i] > 0:
				_recruit_group = i
				break
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	box.add_child(tab_row)
	for i in groups.size():
		var b := _make_button("%s (%d)" % [str(groups[i]["titolo"]), counts[i]])
		_style_tab_button(b, i == _recruit_group)
		b.disabled = counts[i] == 0
		b.pressed.connect(_on_recruit_group_pressed.bind(i))
		tab_row.add_child(b)
	box.add_child(UiTheme.divider())
	var list: Array = groups[_recruit_group]["voci"]
	if list.is_empty():
		var empty := Label.new()
		empty.text = Lang.t("Niente da arruolare qui.")
		box.add_child(empty)
		return
	var flow := _modal_flow(box)
	for pass_index in range(2):
		var wanted_ok := pass_index == 0
		for item in list:
			var e: Dictionary = item
			if bool(e["ok"]) != wanted_ok:
				continue
			var tex := PieceArt.unit_card(_data, _player_id, str(e["unit"])) if AssetLibrary.is_available() else null
			var caption := Lang.t("%s\n%d f · %d a") % [str(e["name"]), int(e["cost"]), int(e["years"])]
			# richiesta di Federico (25/11/2026): gli uomini dell'unita' prima del costo, in grassetto
			var men_text := Lang.t("%d uomini") % int(e["uomini"]) if int(e.get("uomini", 0)) > 0 else ""
			var tile := _modal_tile(tex, MODAL_CARD_SIZE, caption, str(e["tip"]) + Lang.t("\nClic destro: scheda dell'unità"), wanted_ok, men_text)
			tile.pressed.connect(_on_queue_unit.bind(str(e["unit"])))
			tile.gui_input.connect(_on_recruit_tile_input.bind(str(e["unit"])))
			flow.add_child(tile)


func _on_recruit_group_pressed(index: int) -> void:
	_recruit_group = index
	_refresh_province_modal()


## Casella della coda ripetuta (richiesta di Federico, solo per il giocatore): ogni unità completata torna in fondo alla
## coda e si paga di nuovo; senza fondi la coda va in pausa.
func _repeat_toggle(province: ProvinceState) -> CheckBox:
	var box := CheckBox.new()
	box.text = Lang.t("Ripeti la coda")
	box.focus_mode = Control.FOCUS_NONE
	box.button_pressed = province.repeats_units()
	box.tooltip_text = Lang.t("Ogni unità completata torna in fondo alla coda e si paga di nuovo, all'infinito: imposta fino a %d unità e il giro si ripete. Se il tesoro non basta la coda va in pausa e riprende quando i fondi tornano.") % _rules.max_unit_queue
	box.toggled.connect(_on_repeat_toggled.bind(province.id))
	return box


## Righe delle unità della coda ripetuta in attesa di fondi (vuoto se la coda non è in pausa).
func _repeat_pending_lines(province: ProvinceState) -> PackedStringArray:
	var out := PackedStringArray()
	if not province.repeats_units() or province.repeat_pending.is_empty():
		return out
	var start := province.unit_queue.size()
	for i in province.repeat_pending.size():
		var unit_id := province.repeat_pending[i]
		var unit := _state.units.get_unit(unit_id)
		var cost := _state.rules.traits.unit_cost(province.owner, unit) if unit != null else 0
		out.append(Lang.t("%d. %s · in pausa: servono %d denari") % [start + i + 1, CampaignUiPapacy.queue_label(_state, unit_id), cost])
	return out


func _on_repeat_toggled(on: bool, province_id: String) -> void:
	var r := _call_command("set_unit_queue_repeat", [_state, _player_id, province_id, on])
	_after_command(r, Lang.t("Coda ripetuta attivata: le unità completate tornano in fondo alla coda.") if on else Lang.t("Coda ripetuta disattivata."))


## Scheda dei mercenari (fase 8d): compagnie presenti nella provincia, si assoldano subito (costo maggiorato, niente attesa).
func _fill_merc_tab(province: ProvinceState) -> void:
	var box := _modal_merc_box
	var options := GameCommands.mercenary_options(_state, _player_id, province.id)
	var r := _rules.mercenaries
	var note := Label.new()
	note.text = Lang.t("Le compagnie di mercenari si spostano di provincia in provincia, attratte da locande e taverne, e si sciolgono dopo %d anni. Si assoldano subito, costano il %d%% in più e il loro mantenimento è %s; non si riaddestrano.") % [r.max_age, roundi((r.hire_factor - 1.0) * 100.0),
		Lang.t("il doppio del normale") if is_equal_approx(r.upkeep_factor, 2.0) else Lang.t("%s volte quello normale") % str(r.upkeep_factor).replace(".", ",")]
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(MODAL_SIZE.x - 60.0, 0)
	box.add_child(note)
	box.add_child(UiTheme.divider())
	if options.is_empty():
		var none := Label.new()
		none.text = Lang.t("Nessuna compagnia di mercenari in questa provincia quest'anno.")
		box.add_child(none)
		return
	var flow := _modal_flow(box)
	for o in options:
		var unit_id := str(o["unita"])
		var tex := PieceArt.unit_card(_data, _player_id, unit_id) if AssetLibrary.is_available() else null
		var caption := Lang.t("%s\n%d uomini · %d f") % [CampaignUiText.unit_name(unit_id), int(o["uomini"]), int(o["costo"])]
		var tip := Lang.t("%s, %d uomini\nIngaggio: %d denari") % [CampaignUiText.unit_name(unit_id), int(o["uomini"]), int(o["costo"])]
		if not bool(o["ok"]):
			tip += "\n" + str(o["errore"])
		var tile := _modal_tile(tex, MODAL_CARD_SIZE, caption, tip + Lang.t("\nClic destro: scheda dell'unità"), bool(o["ok"]))
		tile.pressed.connect(_on_hire_mercenary.bind(int(o["indice"])))
		tile.gui_input.connect(_on_recruit_tile_input.bind(unit_id))
		flow.add_child(tile)


func _on_hire_mercenary(index: int) -> void:
	if _selected == null:
		return
	var r := GameCommands.hire_mercenary(_state, _player_id, _selected.id, index)
	if bool(r["ok"]):
		GameAudio.play_sfx("soldi")
		_rebuild_markers()
	_after_command(r, Lang.t("Mercenari assoldati: %s, nell'esercito %d.") % [CampaignUiText.unit_name(str(r.get("unita", ""))), int(r.get("esercito", 0))])


## Clic destro su un edificio da costruire: la sua scheda (anche se spento, per vedere che cosa richiede).
func _on_building_tile_input(event: InputEvent, family_id: String, level: int) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
		_show_building_info(family_id, level)
		get_viewport().set_input_as_handled()


func _on_recruit_tile_input(event: InputEvent, unit_id: String) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
		_show_unit_type_info(unit_id)
		get_viewport().set_input_as_handled()


## Nome breve dell'edificio per la didascalia di una tessera (senza «(livello N)»).
func _building_caption(family_id: String, level: int) -> String:
	var it := CampaignUiText.building_label(family_id, level)
	if it == "":
		it = CampaignUiText.building_name(_state, family_id, level).get_slice(" (", 0)
	return it


static func _short(text: String, n: int) -> String:
	return text if text.length() <= n else text.left(n - 1) + "…"


func _modal_queue_row(queue_name: String, index: int, text: String, refund: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var cancel := _make_button(Lang.t("Annulla"))
	cancel.tooltip_text = Lang.t("Rimborso: %d denari") % refund
	cancel.pressed.connect(_on_cancel_queue.bind(queue_name, index))
	row.add_child(cancel)
	return row


## Scheda di unita' ed edifici (richiesta di Federico del 2026-11-15): niente piu' pergamena e illustrazioni dell'originale.
## Nella cornice dei pannelli: a sinistra una vetrina con l'icona rifatta ingrandita e i costi, a destra i dati divisi in
## sezioni a tessere (stato della pila, combattimento, effetti, requisiti, unita' sbloccate) e la descrizione. La misura e'
## fissa, cosi' passando da una scheda all'altra la finestra non salta.
func _build_unit_info_panel() -> void:
	_unit_info_panel = PanelContainer.new()
	_unit_info_panel.visible = false
	_unit_info_panel.z_index = 6
	_unit_info_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_unit_info_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_unit_info_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_unit_info_panel)
	_stack_sheet(_unit_info_panel)
	var margin := _margin()
	_unit_info_panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	# testata: nome, tipo, livelli vicini (edifici) e Chiudi
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	_unit_info_name = Label.new()
	_unit_info_name.theme_type_variation = "Title"
	_unit_info_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_unit_info_name)
	_unit_info_type = Label.new()
	_unit_info_type.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	_unit_info_type.add_theme_font_size_override("font_size", 15)
	titles.add_child(_unit_info_type)
	_unit_info_prev = _make_button(Lang.t("◀ Livello"))
	_unit_info_prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_unit_info_prev)
	_unit_info_next = _make_button(Lang.t("Livello ▶"))
	_unit_info_next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_unit_info_next)
	_unit_info_prev.pressed.connect(func() -> void: _step_building_info(-1))
	_unit_info_next.pressed.connect(func() -> void: _step_building_info(1))
	_unit_info_demolish = _make_button(Lang.t("Demolisci"))
	_unit_info_demolish.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_unit_info_demolish.visible = false
	_unit_info_demolish.pressed.connect(_ask_demolish)
	head.add_child(_unit_info_demolish)
	var close := _make_button(Lang.t("Chiudi (Esc)"))
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: _unit_info_panel.visible = false)
	head.add_child(close)
	root.add_child(UiTheme.divider())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	root.add_child(body)
	# colonna sinistra: vetrina e costi
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(INFO_SHOWCASE.x, 0)
	body.add_child(left)
	_unit_info_showcase = Control.new()
	_unit_info_showcase.custom_minimum_size = INFO_SHOWCASE
	_unit_info_showcase.clip_contents = true
	_unit_info_showcase.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unit_info_showcase.draw.connect(_draw_info_showcase)
	left.add_child(_unit_info_showcase)
	_unit_info_picture = TextureRect.new()
	_unit_info_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_unit_info_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_unit_info_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_unit_info_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unit_info_showcase.add_child(_unit_info_picture)
	var frame := Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw.connect(func() -> void: UiTheme.draw_portrait_frame(frame))
	_unit_info_showcase.add_child(frame)
	_unit_info_costs = GridContainer.new()
	_unit_info_costs.columns = 3
	_unit_info_costs.add_theme_constant_override("h_separation", 6)
	_unit_info_costs.add_theme_constant_override("v_separation", 6)
	left.add_child(_unit_info_costs)
	# colonna destra, a misura fissa con lo scorrimento: nota del comandante, sezioni, descrizione
	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.custom_minimum_size = Vector2(INFO_RIGHT_WIDTH + 16.0, INFO_BODY_HEIGHT)
	body.add_child(right_scroll)
	_unit_info_scroll = right_scroll
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(INFO_RIGHT_WIDTH, 0)
	right_scroll.add_child(right)
	_unit_info_leader = Label.new()
	_unit_info_leader.add_theme_color_override("font_color", UiTheme.INK_TITLE)
	_unit_info_leader.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unit_info_leader.custom_minimum_size = Vector2(INFO_RIGHT_WIDTH, 0)
	right.add_child(_unit_info_leader)
	_unit_info_sections = VBoxContainer.new()
	_unit_info_sections.add_theme_constant_override("separation", 6)
	right.add_child(_unit_info_sections)
	var desc_head := Label.new()
	desc_head.text = Lang.t("Descrizione")
	desc_head.theme_type_variation = "Subtitle"
	right.add_child(desc_head)
	_unit_info_text = Label.new()
	_unit_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unit_info_text.custom_minimum_size = Vector2(INFO_RIGHT_WIDTH, 0)
	_unit_info_text.add_theme_font_size_override("font_size", 15)
	right.add_child(_unit_info_text)


## Fondo della vetrina: carta piu' scura in basso, un'ombra ovale per terra sotto la figura.
func _draw_info_showcase() -> void:
	var c := _unit_info_showcase
	var s := c.size
	var steps := 24
	for i in steps:
		var t := float(i) / float(steps - 1)
		var col := Color("f3e8cc").lerp(Color("cbb68a"), t)
		c.draw_rect(Rect2(0, s.y * float(i) / steps, s.x, s.y / steps + 1.0), col)
	var ground := Vector2(s.x / 2.0, s.y - INFO_GROUND)
	c.draw_set_transform(ground, 0.0, Vector2(1.0, 0.22))
	for k in 6:
		c.draw_circle(Vector2.ZERO, s.x * (0.40 - 0.05 * k), Color(0.25, 0.17, 0.08, 0.06))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Posa l'immagine nella vetrina: centrata, appoggiata a terra, al massimo INFO_PICTURE; le immagini piccole
## dell'originale (carte 50x50 degli agenti) non oltre 3 volte, per non sgranarle.
func _place_info_picture(tex: Texture2D) -> void:
	_unit_info_picture.texture = tex
	_unit_info_picture.material = null
	if tex == null:
		_unit_info_picture.size = Vector2.ZERO
		return
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	var k := minf(INFO_PICTURE / w, INFO_PICTURE / h)
	k = minf(k, 3.0)
	var size := Vector2(w, h) * k
	_unit_info_picture.size = size
	_unit_info_picture.position = Vector2((INFO_SHOWCASE.x - size.x) / 2.0, INFO_SHOWCASE.y - INFO_GROUND * 0.6 - size.y)
	if k > 1.2 and UiTheme.wants_sharpen(tex):   # solo le immagini piccole dell'originale: le rifatte scurivano
		var shader := load(UiTheme.SHARPEN_SHADER) as Shader
		if shader != null:
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter("strength", 0.6)
			_unit_info_picture.material = m


## Tessera di un dato: valore grande sopra, etichetta piccola sotto; `icon` opzionale accanto al valore.
func _info_tile(label: String, value: String, tip: String = "", icon: Texture2D = null) -> PanelContainer:
	var tile := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.PAPER_LIGHT
	sb.border_color = Color(UiTheme.LEATHER, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	tile.add_theme_stylebox_override("panel", sb)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.tooltip_text = tip
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(col)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 5)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	if icon != null:
		var pic := UiTheme.picture(icon, Vector2(20, 20))
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(pic)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 19)
	v.add_theme_color_override("font_color", UiTheme.INK_TITLE)
	var bold := UiTheme.bold_font()
	if bold != null:
		v.add_theme_font_override("font", bold)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(v)
	var l := Label.new()
	l.text = label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(l)
	return tile


## Sezione a tessere: titolo e griglia di `columns` colonne.
func _info_tile_section(title: String, rows: Array, columns: int) -> void:
	if rows.is_empty():
		return
	_info_section_title(title)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_info_sections.add_child(grid)
	for r in rows:
		var row: Array = r
		var tile := _info_tile(str(row[0]), str(row[1]), str(row[2]) if row.size() > 2 else "")
		tile.custom_minimum_size = Vector2((INFO_RIGHT_WIDTH - 6.0 * (columns - 1)) / columns, 0)
		grid.add_child(tile)


## Sezione a righe: etichetta a sinistra, valore che va a capo a destra.
func _info_row_section(title: String, rows: Array) -> void:
	if rows.is_empty():
		return
	_info_section_title(title)
	for r in rows:
		var row: Array = r
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var l := Label.new()
		l.text = str(row[0])
		l.custom_minimum_size = Vector2(INFO_LABEL_WIDTH, 0)
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		line.add_child(l)
		var v := Label.new()
		v.text = str(row[1])
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size = Vector2(INFO_RIGHT_WIDTH - INFO_LABEL_WIDTH - 10.0, 0)
		v.add_theme_font_size_override("font_size", 15)
		line.add_child(v)
		_unit_info_sections.add_child(line)


func _info_section_title(title: String) -> void:
	var t := Label.new()
	t.text = title
	t.theme_type_variation = "Subtitle"
	_unit_info_sections.add_child(t)


## Stato della pila: barra degli uomini e tessere di valore, armi e armatura con lo scudo e la spada del metallo.
func _info_stack_section(stack: Dictionary) -> void:
	if stack.is_empty():
		return
	_info_section_title(Lang.t(CampaignUiUnitInfo.SECTION_STACK))
	var men := int(stack["uomini"])
	var full := maxi(1, int(stack["pieni"]))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = Lang.t("Uomini %d su %d") % [men, int(stack["pieni"])]
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_font_size_override("font_size", 15)
	line.add_child(l)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ratio := clampf(float(men) / float(full), 0.0, 1.0)
	bar.draw.connect(func() -> void:
		var s := bar.size
		bar.draw_rect(Rect2(Vector2.ZERO, s), Color(UiTheme.LEATHER, 0.25))
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x * ratio, s.y)), UiTheme.INK_GOOD if ratio >= 0.75 else (Color("a87a1c") if ratio >= 0.4 else UiTheme.INK_BAD))
		bar.draw_rect(Rect2(Vector2.ZERO, s), Color(UiTheme.LEATHER, 0.8), false, 1.0))
	line.add_child(bar)
	_unit_info_sections.add_child(line)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	_unit_info_sections.add_child(grid)
	var w := (INFO_RIGHT_WIDTH - 12.0) / 3.0
	var tiles: Array[PanelContainer] = [_info_tile(Lang.t("Valore"), str(int(stack["valore"])), Lang.t("Esperienza della pila"))]
	for kind in [["armi", "Armi"], ["armatura", "Armatura"]]:
		var lvl := int(stack[kind[0]])
		var metal := Lang.t(str(TroopUpgrades.METALS[clampi(lvl, 1, TroopUpgrades.MAX_LEVEL)])) if lvl > 0 else Lang.t("nessuno")
		tiles.append(_info_tile(Lang.t(str(kind[1])), ("+%d" % lvl) if lvl > 0 else "—", "%s: %s" % [Lang.t(str(kind[1])), metal], OriginalHud.upgrade_icon(str(kind[0]), lvl)))
	for t in tiles:
		t.custom_minimum_size = Vector2(w, 0)
		grid.add_child(t)


## Unita' che il livello dell'edificio permette di arruolare: carte cliccabili che aprono la scheda dell'unita'.
func _info_unlocks_section(ids: PackedStringArray) -> void:
	if ids.is_empty():
		return
	_info_section_title(Lang.t("Permette di arruolare"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_unit_info_sections.add_child(flow)
	for unit_id in ids:
		var b := Button.new()
		b.theme_type_variation = "Tile"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = INFO_UNLOCK_CARD + Vector2(8, 8)
		b.tooltip_text = Lang.t("%s\nClic: la scheda dell'unità") % CampaignUiText.unit_name(unit_id)
		var tex := PieceArt.unit_card(_data, _player_id, unit_id) if AssetLibrary.is_available() else null
		if tex != null:
			var pic := UiTheme.picture(tex, INFO_UNLOCK_CARD)
			pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			pic.offset_left = 4
			pic.offset_top = 4
			pic.offset_right = -4
			pic.offset_bottom = -4
			b.add_child(pic)
		else:
			b.text = _short(CampaignUiText.unit_name(unit_id), 10)
		b.pressed.connect(_show_unit_type_info.bind(unit_id))
		flow.add_child(b)


func _show_unit_type_info(unit_id: String) -> void:
	_show_unit_data(CampaignUiUnitInfo.info_for_type(_state, unit_id, _player_id))


func _show_unit_info(army_id: int, index: int) -> void:
	_show_unit_data(CampaignUiUnitInfo.info(_state, _state.army(army_id), index))


## Scheda di un edificio (segnalazione di Federico, 2026-11-10): la stessa finestra della scheda dell'unita', con l'icona
## rifatta dell'edificio nella vetrina e i pulsanti per i livelli vicini della stessa famiglia.
func _show_building_info(family_id: String, level: int) -> void:
	var data := CampaignUiBuildingInfo.info(_state, family_id, level, _player_id)
	if data.is_empty():
		return
	data["immagine"] = _building_icon(family_id, int(data["livello"]))
	data["comandante"] = ""
	GameAudio.play_sfx("pergamena")
	_unit_info_building = [family_id, int(data["livello"])]
	_show_unit_data(data)


## Riporta una finestra centrata alla misura minima del contenuto (quando il contenuto cambia misura).
## Si ripete un fotogramma dopo: al primo passaggio le etichette che vanno a capo non conoscono ancora la loro altezza.
func _recenter(panel: Control) -> void:
	for i in 2:
		panel.reset_size()
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
		if i == 0:
			await get_tree().process_frame


## «Demolisci» solo sulla scheda del livello piu' alto di un edificio costruito nella provincia propria scelta; spento con il
## motivo se non si puo' (in coda di costruzione, serve a un altro edificio).
func _refresh_demolish_button(data: Dictionary) -> void:
	_unit_info_demolish.visible = false
	if data.is_empty() or _selected == null or _state == null:
		return
	var province := _state.province(_selected.id)
	var family := str(data.get("famiglia", ""))
	if province == null or province.owner != _player_id or province.level_of(family) != int(data.get("livello", 0)):
		return
	var check := GameCommands.can_demolish_building(_state, _player_id, province.id, family)
	_unit_info_demolish.visible = true
	_unit_info_demolish.disabled = not bool(check["ok"])
	if bool(check["ok"]):
		_unit_info_demolish.tooltip_text = Lang.t("Demolisci l'edificio: tornano %d denari (la metà del costo). Chiede conferma.") % int(check["rimborso"])
	else:
		_unit_info_demolish.tooltip_text = CampaignUiText.order_error_text(_state, str(check["errore"]))


func _ask_demolish() -> void:
	if _unit_info_building.size() < 2 or _selected == null:
		return
	var family := str(_unit_info_building[0])
	var province_id := _selected.id
	var check := GameCommands.can_demolish_building(_state, _player_id, province_id, family)
	if not bool(check["ok"]):
		_toast_show(CampaignUiText.order_error_text(_state, str(check["errore"])))
		return
	var name_text := CampaignUiText.building_name(_state, family, int(check["livello"]))
	_confirm_ask(Lang.t("Demolire %s?") % name_text,
		Lang.t("L'edificio scende di un livello e tornano nel tesoro %d denari. Non si annulla.") % int(check["rimborso"]),
		Lang.t("Demolisci"), Lang.t("Annulla"), func() -> void:
			var r := GameCommands.demolish_building(_state, _player_id, province_id, family)
			_unit_info_panel.visible = false
			if bool(r["ok"]):
				GameAudio.play_sfx("soldi")
			_after_command(r, Lang.t("Demolito: %s (+%d denari).") % [name_text, int(r.get("rimborso", 0))]))


func _step_building_info(delta: int) -> void:
	if _unit_info_building.size() < 2:
		return
	_show_building_info(str(_unit_info_building[0]), int(_unit_info_building[1]) + delta)


func _show_unit_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	var building := data.has("famiglia")
	if not building:
		_unit_info_building = []
	var tex: Texture2D = data.get("immagine")
	if not building and AssetLibrary.is_available():
		tex = PieceArt.unit_card(_data, _player_id, str(data["unita"]))
	_place_info_picture(tex)
	_unit_info_showcase.queue_redraw()
	_unit_info_name.text = str(data["nome"])
	_unit_info_type.text = str(data["tipo"])
	_unit_info_prev.visible = building and str(data.get("precedente", "")) != ""
	_unit_info_next.visible = building and str(data.get("successivo", "")) != ""
	_unit_info_prev.tooltip_text = str(data.get("precedente", ""))
	_unit_info_next.tooltip_text = str(data.get("successivo", ""))
	_refresh_demolish_button(data if building else {})
	var leader := str(data["comandante"])
	_unit_info_leader.text = leader
	_unit_info_leader.visible = leader != ""
	_clear_children(_unit_info_costs)
	for r in data.get("costi", []):
		var row: Array = r
		var parts := str(row[1]).split(" ", true, 1)
		var tile := _info_tile(str(row[0]) + ("" if parts.size() < 2 else " (%s)" % parts[1]), parts[0], "%s: %s" % [row[0], row[1]])
		tile.custom_minimum_size = Vector2((INFO_SHOWCASE.x - 12.0) / 3.0, 0)
		_unit_info_costs.add_child(tile)
	_clear_children(_unit_info_sections)
	if building:
		_info_tile_section(Lang.t("Effetti"), data.get("effetti", []), 2)
		if (data.get("effetti", []) as Array).is_empty():
			_info_row_section(Lang.t("Effetti"), [["", Lang.t("Nessun effetto diretto: serve ad altri edifici o alle unità.")]])
		_info_row_section(Lang.t("Requisiti"), data.get("requisiti", []))
		_info_unlocks_section(data.get("sblocca", PackedStringArray()))
	else:
		_info_stack_section(data.get("pila", {}))
		var fight: Array = data.get("combattimento", [])
		_info_tile_section(Lang.t(CampaignUiUnitInfo.SECTION_SEA if bool(data.get("nave", false)) else CampaignUiUnitInfo.SECTION_FIGHT), fight, 3 if fight.size() <= 6 else 4)
		_info_row_section(Lang.t(CampaignUiUnitInfo.SECTION_RECRUIT), data.get("arruolamento", []))
	var text := str(data["descrizione"])
	_unit_info_text.text = text if text != "" else Lang.t("Nessuna descrizione disponibile.")
	_unit_info_scroll.scroll_vertical = 0
	_unit_info_panel.visible = true
	_recenter.call_deferred(_unit_info_panel)


## Schermata di fine partita: titolo, testo, classifica; «Continua a giocare» solo dopo la vittoria per dominio.
func _build_end_panel() -> void:
	_end_panel = PanelContainer.new()
	_end_panel.visible = false
	_end_panel.z_index = 8
	_end_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_end_panel)
	_stack_sheet(_end_panel)
	var margin := _margin()
	_end_panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)
	# immagine di fine partita con il titolo scritto nel nastro vuoto in cima (EventArt.end_ribbon)
	_end_picture_box = Control.new()
	_end_picture_box.custom_minimum_size = END_PICTURE_SIZE
	_end_picture_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_end_picture_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_end_picture_box)
	_end_picture = UiTheme.picture(null, END_PICTURE_SIZE)
	_end_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_end_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_picture_box.add_child(_end_picture)
	_end_ribbon_title = Label.new()
	_end_ribbon_title.theme_type_variation = "Title"
	_end_ribbon_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_ribbon_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_end_ribbon_title.clip_text = true
	var ribbon := EventArt.end_ribbon()
	if ribbon.size.x > 0.0:
		var k := END_PICTURE_SIZE.x / EventArt.END_SIZE.x
		_end_ribbon_title.position = ribbon.position * k
		_end_ribbon_title.size = ribbon.size * k
		_end_ribbon_title.add_theme_font_size_override("font_size", int(ribbon.size.y * k * 0.72))
	_end_picture_box.add_child(_end_ribbon_title)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	row.add_child(box)
	_end_title = Label.new()
	_end_title.theme_type_variation = "Title"
	box.add_child(_end_title)
	_end_text = Label.new()
	_end_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_text.custom_minimum_size = Vector2(470.0, 0.0)
	box.add_child(_end_text)
	box.add_child(UiTheme.divider())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(490.0, 240.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_end_box = VBoxContainer.new()
	_end_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_end_box)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_end_continue_button = _make_button(Lang.t("Continua a giocare"))
	_end_continue_button.tooltip_text = Lang.t("Resta in gioco fino all'anno finale: la vittoria per dominio è già tua.")
	_end_continue_button.pressed.connect(_on_continue_after_victory)
	buttons.add_child(_end_continue_button)
	_end_close_button = _make_button(Lang.t("Vedi la mappa (Esc)"))
	_end_close_button.pressed.connect(_on_end_close)
	buttons.add_child(_end_close_button)


func _show_end_screen() -> void:
	if _state == null or not CampaignUiVictory.has_end_screen(_state):
		return
	_court_panel.visible = false
	_diplomacy_panel.visible = false
	_standings_panel.visible = false
	_hide_mission_menu()
	var screen := CampaignUiVictory.end_screen(_state, _player_id)
	_end_title.text = str(screen["titolo"])
	_end_text.text = str(screen["testo"])
	_clear_children(_end_box)
	var rows: Array = screen["righe"]
	var player_won := not rows.is_empty() and bool(rows[0]["giocatore"])
	var f := _data.faction(_player_id) if _data != null else null
	var art := EventArt.end_texture(_player_id, f.religion if f != null else "", str(screen["esito"]), player_won)
	_end_picture.texture = art
	_end_picture_box.visible = art != null
	_end_ribbon_title.text = str(screen["titolo"])
	var won := str(screen["esito"]) == VictoryState.DOMINATION or (str(screen["esito"]) != VictoryState.DEFEAT and player_won)
	GameAudio.play_music(("vittoria_" if won else "sconfitta_") + ("islamica" if _is_islamic_player() else "cristiana"))
	# con l'immagine il titolo sta nel nastro; senza, resta in testa al testo
	_end_title.visible = art == null
	_end_box.add_child(_standings_grid(rows))
	var can_continue := bool(screen["puo_continuare"])
	_end_continue_button.visible = can_continue
	_end_close_button.text = Lang.t("Fermati qui (Esc)") if can_continue else Lang.t("Vedi la mappa (Esc)")
	_end_panel.visible = true


func _on_end_close() -> void:
	_end_panel.visible = false


func _on_continue_after_victory() -> void:
	if _state == null:
		return
	var r := GameCommands.continue_after_victory(_state, _player_id)
	if not bool(r["ok"]):
		_toast_show(str(r["errore"]))
		return
	_end_panel.visible = false
	_refresh_top_bar()
	_toast_show(Lang.t("Si continua a giocare: la vittoria per dominio è registrata."))


# --- Pannello della diplomazia (fase 5a) ------------------------------------------------

func _toggle_diplomacy() -> void:
	if _state == null or not _ready_to_navigate:
		return
	_diplomacy_panel.visible = not _diplomacy_panel.visible
	GameAudio.play_sfx("pergamena" if _diplomacy_panel.visible else "chiudi")
	if _diplomacy_panel.visible:
		_court_panel.visible = false
		_standings_panel.visible = false
		_hide_mission_menu()
	_refresh_diplomacy_panel()


## Ricostruisce il pannello della diplomazia dallo stato attuale (solo se è aperto): una riga per fazione viva,
## il giocatore in cima (CampaignUiAgents.diplomacy_rows).
func _refresh_diplomacy_panel() -> void:
	if _diplomacy_panel == null or not _diplomacy_panel.visible or _state == null:
		return
	_clear_children(_diplomacy_box)
	_diplomacy_title.text = Lang.t("Diplomazia · %s · anno %d") % [FactionStyle.full_name_of(_player_id), _state.year]
	_diplomacy_shield.texture = AssetLibrary.faction_shield(_player_id)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	_diplomacy_box.add_child(grid)
	for header in CampaignUiPapacy.diplomacy_headers():
		var head := Label.new()
		head.text = header
		head.theme_type_variation = "Subtitle"
		grid.add_child(head)
	for row in CampaignUiPapacy.diplomacy_rows(_state, _player_id):
		var cells := CampaignUiPapacy.diplomacy_cells(row)
		var color := Color.WHITE
		var relation := str(row["relazione"])
		if relation == GameState.REL_WAR:
			color = BAD_COLOR
		elif relation == GameState.REL_ALLIANCE:
			color = UiTheme.INK_GOOD
		elif relation == GameState.REL_TRUCE:
			color = UiTheme.INK_BLUE
		# fase 8: scudo della fazione al posto del quadratino di colore, icona della religione
		var first := HBoxContainer.new()
		first.add_theme_constant_override("separation", 6)
		first.add_child(UiTheme.shield(str(row["fazione"]), Vector2(20, 24)))
		var faction_cell := Label.new()
		faction_cell.text = cells[0]
		first.add_child(faction_cell)
		grid.add_child(first)
		for c in range(1, cells.size()):
			var cell := Label.new()
			cell.text = cells[c]
			if c == 2 and str(row.get("chiave_religione", "")) != "":
				var rel_box := HBoxContainer.new()
				rel_box.add_theme_constant_override("separation", 4)
				rel_box.add_child(UiIcons.icon("religioni", str(row["chiave_religione"]), cells[c], UiIcons.SMALL_SIZE, ""))
				rel_box.add_child(cell)
				grid.add_child(rel_box)
				continue
			if c == 3 and not (row.get("guerre", []) as Array).is_empty():
				grid.add_child(_war_cell(row))
				continue
			if c == 1 and color != Color.WHITE:
				cell.add_theme_color_override("font_color", color)
			elif c == 5 and bool(row["scomunicata"]):
				cell.add_theme_color_override("font_color", BAD_COLOR)
			grid.add_child(cell)
	_diplomacy_box.add_child(UiTheme.divider())
	var papacy_row := HBoxContainer.new()
	papacy_row.add_theme_constant_override("separation", 10)
	_diplomacy_box.add_child(papacy_row)
	var pope := _state.leader_of(GameState.PAPAL)
	var pope_tex := PortraitArt.portrait(_data, pope) if pope != null and AssetLibrary.is_available() else null
	if pope_tex != null:   # ADR-059: il ritratto del Papa accanto alla riga del Papato; clic = la sua scheda
		var pope_frame := UiTheme.portrait(pope_tex, Vector2(48, 71))
		pope_frame.tooltip_text = Lang.t("Papa %s") % pope.full_name()
		pope_frame.mouse_filter = Control.MOUSE_FILTER_STOP
		var pope_id := pope.id
		pope_frame.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed:
				_show_character_info(pope_id))
		papacy_row.add_child(pope_frame)
	var papacy := Label.new()
	papacy.text = CampaignUiPapacy.papacy_line(_state)
	papacy.theme_type_variation = "Subtitle"
	papacy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	papacy_row.add_child(papacy)


## Cella «In guerra con» della diplomazia: scudo e nome di ogni nemico, a capo oltre i 300 px; in rosso le guerre
## che riguardano il giocatore.
func _war_cell(row: Dictionary) -> Control:
	var flow := HFlowContainer.new()
	flow.custom_minimum_size = Vector2(300, 0)
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 2)
	var mine := bool(row["giocatore"])
	for enemy in row["guerre"]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)
		item.add_child(UiTheme.shield(str(enemy), Vector2(16, 19)))
		var name_label := Label.new()
		name_label.text = CampaignUiText.faction_name(str(enemy))
		if mine or SimUtil.norm(str(enemy)) == SimUtil.norm(_player_id):
			name_label.add_theme_color_override("font_color", BAD_COLOR)
		item.add_child(name_label)
		flow.add_child(item)
	return flow


## Ricostruisce il pannello della corte dallo stato attuale (solo se è aperto).
func _refresh_court_panel() -> void:
	if _court_panel == null or not _court_panel.visible or _state == null:
		return
	_clear_children(_court_box)
	_court_title.text = Lang.t("Corte · %s · anno %d") % [FactionStyle.full_name_of(_player_id), _state.year]
	_court_shield.texture = AssetLibrary.faction_shield(_player_id)
	if not _state.has_dynasty(_player_id):
		_court_text(Lang.t("Questa partita non ha dinastie: nessun personaggio da mostrare."), Color.WHITE)
		return
	_add_council_hall()
	for section in CampaignUiText.court_sections(_state, _player_id):
		_court_box.add_child(UiTheme.divider())
		var heading := _court_text(str(section["titolo"]), Color.WHITE)
		heading.theme_type_variation = "Subtitle"
		var entries: Array = section["voci"]
		for entry in entries:
			var entry_data: Dictionary = entry
			_add_court_entry(entry_data)


const COUNCIL_SEAT_WIDTH := 128.0
const COUNCIL_SEAT_PORTRAIT := Vector2(80, 118)
const COUNCIL_THRONE_PORTRAIT := Vector2(128, 188)
const COUNCIL_ARC_STEP := 30.0
const COUNCIL_PADDING_V := 20        ## margine sopra e sotto i seggi, dentro la scheda del consiglio
const COUNCIL_PADDING_H := 12       ## i seggi piu' lontani dal trono scendono di tanto: la mezzaluna del consiglio


## Sala del consiglio in testa alla corte (richiesta di Federico del 20/11/2026): il re al centro, piu' grande, e ai lati a
## mezzaluna i ritratti di chi ha le cariche di corte (CampaignUiText.council_seats: le piu' alte accanto al trono). Seggio
## vacante: cornice vuota; carica non ancora sbloccata: seggio sbiadito con l'edificio da costruire. Clic su un ritratto: la
## scheda del personaggio; clic su un seggio vacante: la provincia sulla scheda Governo, dove si concede.
func _add_council_hall() -> void:
	var hall := CampaignUiText.council_seats(_state, _player_id)
	var left: Array = hall["sinistra"]
	var right: Array = hall["destra"]
	var king := _state.character(int(hall["capo"])) if int(hall["capo"]) > 0 else null
	if king == null and left.is_empty() and right.is_empty():
		return
	_court_box.add_child(UiTheme.divider())
	var heading := _court_text(Lang.t("Sala del consiglio"), Color.WHITE)
	heading.theme_type_variation = "Subtitle"
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	# margine sopra e sotto (richiesta di Federico del 20/11/2026): ritratti e pulsanti non toccano i bordi della scheda
	var pad := MarginContainer.new()
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, COUNCIL_PADDING_V)
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, COUNCIL_PADDING_H)
	card.add_child(pad)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	pad.add_child(row)
	for seat in left:
		row.add_child(_council_seat(seat))
	if king != null:
		row.add_child(_council_throne(king))
	for seat in right:
		row.add_child(_council_seat(seat))
	_court_box.add_child(card)


## Il trono: ritratto grande del capo con il titolo (Re, Imperatore Dio...) e il nome.
func _council_throne(king: Character) -> Control:
	var tex := PortraitArt.portrait(_data, king)
	var rank := CampaignUiText.leader_rank(_state, king.faction)   # «re», o il titolo proprio (Imperatore Dio)
	var lines := [[rank.left(1).to_upper() + rank.substr(1), UiTheme.INK_TITLE, true], [king.full_name(), UiTheme.INK, false]]
	var tip := Lang.t("%s\nClic: la sua scheda") % king.full_name()
	return _council_box(COUNCIL_SEAT_WIDTH + 28.0, 0.0, UiTheme.portrait(tex, COUNCIL_THRONE_PORTRAIT), lines, tip,
		_show_character_info.bind(king.id))


## Seggio di una carica: ritratto del titolare, nome della carica, bonus e titolare; scende con la distanza dal trono. Sotto,
## i comandi (richiesta di Federico del 20/11/2026: «dal consiglio possa assegnare e rimuovere le cariche»): «Concedi» o
## «Cambia» apre l'elenco dei personaggi (presenti nella sede per primi, in blu chi ha gia' una carica), «Revoca» la toglie.
func _council_seat(seat: Dictionary) -> Control:
	var holder := _state.character(int(seat["titolare"])) if int(seat["titolare"]) > 0 else null
	var where := str(seat["provincia"])
	var office := str(seat["nome"])
	var bonus := str(seat["bonus"])
	var picture: Control
	var lines: Array = [[office, UiTheme.INK_TITLE, true]]
	if bonus != "":
		lines.append([bonus, UiTheme.INK_FAINT, false])
	var tip := office + ((" (%s)" % bonus) if bonus != "" else "")
	if holder != null:
		picture = UiTheme.portrait(PortraitArt.portrait(_data, holder), COUNCIL_SEAT_PORTRAIT)
		lines.append([holder.full_name(), UiTheme.INK, false])
		tip += Lang.t("\n%s\nClic: la sua scheda") % holder.full_name()
	else:
		picture = _council_empty_frame(Lang.t("Vacante") if where != "" else Lang.t("Da costruire"))
		lines.append([Lang.t("Vacante") if where != "" else str(seat["serve"]), UiTheme.INK_FAINT, false])
		if where != "":
			tip += Lang.t("\nVacante: clic per concederla (sede: %s)") % CampaignUiText.region_name(_state, where)
		else:
			tip += Lang.t("\nSi sblocca costruendo: %s") % str(seat["serve"])
	var drop := COUNCIL_ARC_STEP * float(int(seat["vicinanza"]))
	var building := str(seat["edificio"])
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var action := Callable()
	var box: PanelContainer
	if holder != null:
		action = _show_character_info.bind(holder.id)
	box = _council_box(COUNCIL_SEAT_WIDTH, drop, picture, lines, tip, action)
	column.add_child(box)
	if where == "":
		box.modulate = Color(1, 1, 1, 0.55)
		return column
	var grant := _council_button((Lang.t("Cambia") if holder != null else Lang.t("Concedi")) + " ▾")
	grant.tooltip_text = Lang.t("Concedi la carica di %s: chi la deteneva la perde e la sua lealtà cala di %d; una sola carica a testa.") % [office, _rules.dynasty.revoke_loyalty_drop]
	grant.disabled = CampaignUiText.eligible_officers(_state, _player_id, building).is_empty()
	grant.pressed.connect(_open_office_menu.bind(grant, building, where))
	column.add_child(grant)
	if holder != null:
		var revoke := _council_button(Lang.t("Revoca"))
		revoke.tooltip_text = Lang.t("Toglie la carica: la lealtà del titolare cala di %d.") % _rules.dynasty.revoke_loyalty_drop
		revoke.pressed.connect(_on_revoke_office.bind(holder.id))
		column.add_child(revoke)
	else:
		# il seggio vacante si concede anche con un clic sulla cornice
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.gui_input.connect(func(event: InputEvent) -> void:
			var click := event as InputEventMouseButton
			if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not grant.disabled:
				_open_office_menu(grant, building, where))
	return column


## Pulsante piccolo sotto un seggio del consiglio.
func _council_button(text: String) -> Button:
	var b := _make_button(text)
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(COUNCIL_SEAT_WIDTH - 16.0, 0.0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


## Cornice vuota della misura di un ritratto, con una parola al centro.
func _council_empty_frame(word: String) -> Control:
	var frame := UiTheme.portrait(null, COUNCIL_SEAT_PORTRAIT)
	var back := ColorRect.new()
	back.color = Color(UiTheme.PAPER_DARK, 0.7)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(back)
	frame.move_child(back, 0)
	var l := Label.new()
	l.text = word
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.offset_left = 4
	l.offset_right = -4
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	frame.add_child(l)
	return frame


## Seggio cliccabile: rientro in alto `drop`, immagine centrata e righe di testo [testo, colore, grassetto]; si scurisce al
## passaggio del mouse se ha un'azione (`action`, Callable vuota = nessuna). Contenitore che prende la misura dal contenuto.
func _council_box(width: float, drop: float, picture: Control, lines: Array, tip: String, action: Callable) -> PanelContainer:
	var box := PanelContainer.new()
	box.tooltip_text = tip
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var hover := UiTheme._flat(Color(UiTheme.PAPER_DARK, 0.55), Color(0, 0, 0, 0), 0, 6, 2)
	var clear := StyleBoxEmpty.new()            # stessi margini dello sfondo al passaggio: il seggio non si sposta (20/11/2026)
	clear.set_content_margin_all(2)
	box.add_theme_stylebox_override("panel", clear)
	if action.is_valid():
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.mouse_entered.connect(func() -> void: box.add_theme_stylebox_override("panel", hover))
		box.mouse_exited.connect(func() -> void: box.add_theme_stylebox_override("panel", clear))
		box.gui_input.connect(func(event: InputEvent) -> void:
			var click := event as InputEventMouseButton
			if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				action.call())
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(width, drop)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(picture)
	col.add_child(center)
	for line in lines:
		var l := Label.new()
		l.text = str(line[0])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width, 0.0)
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", line[1])
		if bool(line[2]) and UiTheme.bold_font() != null:
			l.add_theme_font_override("font", UiTheme.bold_font())
		col.add_child(l)
	return box


func _court_text(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(COURT_TEXT_WIDTH, 0.0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if color != Color.WHITE:
		l.add_theme_color_override("font_color", color)
	_court_box.add_child(l)
	return l


## Voce della corte (fase 8): ritratto dell'originale, nome con il simbolo di re o erede, attributi come icone, titolo, carica,
## esercito, vizi e virtu'; se comanda un esercito, il pulsante che lo seleziona sulla mappa.
func _add_court_entry(entry: Dictionary) -> void:
	var c := _state.character(int(entry.get("personaggio", 0))) if int(entry.get("personaggio", 0)) > 0 else null
	if c != null:
		_add_court_card(c, entry)
		return
	var army_id := int(entry.get("esercito", 0))
	if army_id <= 0 or _state.army(army_id) == null:
		_court_text(str(entry["testo"]), Color.WHITE)
		return
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = str(entry["testo"])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(COURT_TEXT_WIDTH, 0.0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var go := _make_button(Lang.t("Vai all'esercito"))
	go.tooltip_text = Lang.t("Chiude la corte e seleziona l'esercito sulla mappa.")
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(_on_court_army_pressed.bind(army_id))
	row.add_child(go)
	_court_box.add_child(row)


func _add_court_card(c: Character, entry: Dictionary) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var tex := PortraitArt.portrait(_data, c)
	if tex != null:
		row.add_child(UiTheme.portrait(tex, Vector2(72, 106)))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var lines := str(entry["testo"]).split("\n")
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	col.add_child(name_row)
	var marker := ""
	if c.role == Character.ROLE_LEADER:
		marker = "king"
	elif c.role == Character.ROLE_HEIR:
		marker = "heir"
	if marker != "":
		name_row.add_child(UiIcons.icon("attributi", marker, Lang.t("Capo della fazione") if marker == "king" else Lang.t("Erede"), Vector2(12, 26), ""))
	var name_label := Label.new()
	name_label.text = lines[0] if not lines.is_empty() else c.full_name()
	name_label.theme_type_variation = "Subtitle"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	if c.role != Character.ROLE_PRINCESS or c.command > 0:
		col.add_child(_attribute_row(c))
	# le altre righe di character_lines tranne quella degli attributi (ora icone)
	var rest := PackedStringArray()
	for i in range(2, lines.size()):
		rest.append(lines[i].strip_edges())
	if not rest.is_empty():
		var detail := Label.new()
		detail.text = "\n".join(rest)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(detail)
	var army_id := int(entry.get("esercito", 0))
	if army_id > 0 and _state.army(army_id) != null:
		var go := _make_button(Lang.t("Vai all'esercito"))
		go.tooltip_text = Lang.t("Chiude la corte e seleziona l'esercito sulla mappa.")
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.pressed.connect(_on_court_army_pressed.bind(army_id))
		row.add_child(go)
	_court_box.add_child(card)


## Dalla corte alla mappa: seleziona l'esercito e la sua regione e centra la vista.
func _on_court_army_pressed(army_id: int) -> void:
	var army := _state.army(army_id)
	if army == null:
		return
	_court_panel.visible = false
	var region: CampaignData.Region = _data.region(army.region)
	if region != null:
		_select(region)
	_select_army(army_id)
	if _anchors.has(army.region):
		var target: Vector2 = _anchors[army.region]
		_camera.position = target
		_clamp_camera()


## Scheda «Agenti» della finestra dei messaggi: una riga per agente proprio (CampaignUiAgents.roster) con «Raggiungi».
func _refresh_agents_tab() -> void:
	if _agents_list == null or _state == null or _events_tabs.current_tab != 1:
		return
	_clear_children(_agents_list)
	var rows := CampaignUiAgents.roster(_state, _player_id)
	if rows.is_empty():
		var none := Label.new()
		none.text = Lang.t("Nessun agente in campo.")
		_agents_list.add_child(none)
		return
	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var agent := _state.agent(int(row["id"]))
		var tex := PortraitArt.agent_portrait(_data, agent) if agent != null and AssetLibrary.is_available() else null
		if tex != null:
			line.add_child(UiTheme.portrait(tex, Vector2(34, 50)))
		var text := Label.new()
		text.text = "%s  %s\n%s · %s" % [str(row["titolo"]), str(row["stelle"]), str(row["dove"]), str(row["attivita"])]
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		var go := _make_button(Lang.t("Raggiungi"))
		go.tooltip_text = Lang.t("Chiude la finestra, centra la mappa sull'agente e lo seleziona.")
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.pressed.connect(_on_reach_agent_pressed.bind(int(row["id"])))
		line.add_child(go)
		_agents_list.add_child(line)


## «Raggiungi»: chiude la finestra dei messaggi, seleziona la regione e l'agente e porta la camera sopra di lui.
func _on_reach_agent_pressed(agent_id: int) -> void:
	var agent := _state.agent(agent_id)
	if agent == null:
		return
	_events_panel.visible = false
	var region: CampaignData.Region = _data.region(agent.region)
	if region != null:
		_select(region)
	_select_agent(agent_id)
	if _anchors.has(agent.region):
		var target: Vector2 = _anchors[agent.region]
		_camera.position = target
		_clamp_camera()


## Chiude il resoconto dell'anno; se la partita e' finita, dopo il resoconto si apre la schermata di fine partita.
func _hide_events() -> void:
	_events_panel.visible = false
	if _end_pending:
		_show_next_popup()


func _margin() -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	return m


func _show_message(text: String) -> void:
	_message.text = CampaignUiText.humanize_ids(_state, text) if _state != null and _state.campaign != null else text
	_message.visible = true


## Proventi delle province (richiesta di Federico, 2026-11-10): tabella delle province proprie con le voci del reddito
## previsto quest'anno, tassa e motivo dei redditi nulli; in fondo totali, mantenimento e saldo (CampaignUiEconomy).
func _toggle_economy() -> void:
	if _economy_panel == null:
		_economy_panel = PanelContainer.new()
		_economy_panel.z_index = 5
		_economy_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_economy_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_economy_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		_ui.add_child(_economy_panel)
		_stack_sheet(_economy_panel)
		var margin := _margin()
		_economy_panel.add_child(margin)
		var outer := VBoxContainer.new()
		outer.add_theme_constant_override("separation", 6)
		margin.add_child(outer)
		var head := HBoxContainer.new()
		outer.add_child(head)
		var title := Label.new()
		title.text = Lang.t("Economia: proventi delle province")
		title.theme_type_variation = "Title"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var close := _make_button(Lang.t("Chiudi (F1)"))
		close.pressed.connect(func() -> void: _economy_panel.visible = false)
		head.add_child(close)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(880, 470)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		outer.add_child(scroll)
		_economy_box = VBoxContainer.new()
		_economy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(_economy_box)
		_economy_panel.visible = false
	_economy_panel.visible = not _economy_panel.visible
	if _economy_panel.visible:
		GameAudio.play_sfx("pergamena")
		_refresh_economy()


func _refresh_economy() -> void:
	if _economy_panel == null or not _economy_panel.visible:
		return
	_clear_children(_economy_box)
	var r := CampaignUiEconomy.report(_state, _player_id)
	# righe a colonne fisse (non una griglia): sotto una riga si apre il dettaglio dei porti raggiunti (richiesta di Federico
	# del 2026-11-13: niente elenco lungo di rotte in una riga)
	var head := _economy_row()
	for i in ECONOMY_COLUMNS.size():
		var h := Label.new()
		h.text = Lang.t(str(ECONOMY_COLUMNS[i][0]))
		h.theme_type_variation = "Subtitle"
		h.add_theme_font_size_override("font_size", 15)
		h.custom_minimum_size.x = float(ECONOMY_COLUMNS[i][1])
		if i in [1, 2, 3, 4]:
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(h)
	_economy_box.add_child(head)
	for row_info in r["righe"]:
		var d: Dictionary = row_info
		var region_id := str(d["provincia"])
		var row := _economy_row()
		_economy_box.add_child(row)
		var name_button := Button.new()
		name_button.text = str(d["nome"])
		name_button.flat = true
		name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_button.custom_minimum_size.x = float(ECONOMY_COLUMNS[0][1])
		name_button.clip_text = true
		name_button.add_theme_color_override("font_color", UiTheme.INK_TITLE)
		name_button.add_theme_color_override("font_hover_color", UiTheme.INK_BAD)
		name_button.tooltip_text = Lang.t("Mostra la provincia")
		name_button.pressed.connect(func() -> void:
			var region := _state.campaign.region(region_id)
			if region == null:
				return
			_selected_castle = ""
			_select(region)
			if _anchors.has(region_id):
				_camera.position = _anchors[region_id]
				_clamp_camera())
		row.add_child(name_button)
		var keys := ["agricoltura", "miniere", "commercio", "totale"]
		for i in keys.size():
			var v := Label.new()
			v.text = str(int(d[keys[i]]))
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			v.custom_minimum_size.x = float(ECONOMY_COLUMNS[i + 1][1])
			if keys[i] == "totale":
				v.add_theme_color_override("font_color", UiTheme.INK_TITLE)
			row.add_child(v)
		var tax := Label.new()
		tax.text = str(d["tassa"])
		tax.custom_minimum_size.x = float(ECONOMY_COLUMNS[5][1])
		row.add_child(tax)
		var ports: Array = d.get("porti", [])
		if str(d["nota"]) != "":
			var note := Label.new()
			note.text = str(d["nota"])
			note.add_theme_color_override("font_color", UiTheme.INK_BAD)
			row.add_child(note)
		elif not ports.is_empty():
			var open := _economy_open == region_id
			var toggle := Button.new()
			toggle.flat = true
			toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
			toggle.text = "%s %d %s" % ["▾" if open else "▸", ports.size(), Lang.t("porto") if ports.size() == 1 else Lang.t("porti")]
			toggle.tooltip_text = Lang.t("Porti stranieri raggiunti dalle flotte e quanto rende ciascuno")
			toggle.add_theme_color_override("font_color", UiTheme.INK_BLUE)
			toggle.add_theme_color_override("font_hover_color", UiTheme.INK_BAD)
			toggle.pressed.connect(func() -> void:
				_economy_open = "" if _economy_open == region_id else region_id
				_refresh_economy())
			row.add_child(toggle)
			if open:
				_economy_box.add_child(_economy_ports(d))
	_economy_box.add_child(UiTheme.divider())
	var foot := GridContainer.new()
	foot.columns = 2
	foot.add_theme_constant_override("h_separation", 18)
	_economy_box.add_child(foot)
	var last: Dictionary = r["anno_scorso"]
	var lines := [
		[Lang.t("Agricoltura"), str(int(r["agricoltura"]))],
		[Lang.t("Miniere"), str(int(r["miniere"]))],
		[Lang.t("Commercio"), str(int(r["commercio"]))],
		[Lang.t("Proventi previsti quest'anno"), Lang.t("%d denari") % int(r["totale"])],
		[Lang.t("Mantenimento delle forze"), Lang.t("-%d denari") % int(r["mantenimento"])],
		[Lang.t("Saldo previsto"), Lang.t("%+d denari") % int(r["saldo"])],
		[Lang.t("Tesoro"), Lang.t("%d denari") % int(r["tesoro"])],
	]
	if not last.is_empty():
		lines.append([Lang.t("Reddito netto dell'anno scorso"), Lang.t("%+d denari") % int(last.get("netto", 0))])
		var last_spent := CampaignUiText.spending_line(last.get("spese", {}))
		if last_spent != "":
			lines.append([Lang.t("Spese dell'anno scorso"), last_spent])
		if last.has("saldo"):
			lines.append([Lang.t("Saldo reale dell'anno scorso"), Lang.t("%+d denari") % int(last["saldo"])])
	var f_now := _state.faction(_player_id)
	if f_now != null and CampaignUiText.spending_line(f_now.spent) != "":
		lines.append([Lang.t("Spese di quest'anno finora"), CampaignUiText.spending_line(f_now.spent)])
	for pair in lines:
		var k := Label.new()
		k.text = str(pair[0])
		k.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		foot.add_child(k)
		var v2 := Label.new()
		v2.text = str(pair[1])
		foot.add_child(v2)
	var hint := Label.new()
	hint.text = Lang.t("Il reddito si calcola a fine anno con le stesse regole: le province assediate o con eserciti nemici non rendono nulla; la tassa vale per l'agricoltura.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	_economy_box.add_child(hint)


## Colonne della finestra Economia: titolo e larghezza minima.
const ECONOMY_COLUMNS := [["Provincia", 170], ["Agricoltura", 92], ["Miniere", 72], ["Commercio", 92], ["Totale", 76],
		["Tassa", 84], ["Rotte via mare", 150]]


func _economy_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	return row


## Dettaglio del commercio di una provincia: le tre parti e i porti raggiunti, dal piu' redditizio, su due colonne; oltre i
## primi 12 una riga con il resto (ADR-054: ogni porto pesa secondo la sua ricchezza).
func _economy_ports(d: Dictionary) -> Control:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.36, 0.26, 0.14, 0.08)
	style.border_color = Color(UiTheme.INK_FAINT, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", style)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	box.add_child(inner)
	var parts := Label.new()
	parts.text = Lang.t("Commercio di %s: locale %d · via mare %d · importazioni %d") % [
		str(d["nome"]), int(d["commercio_locale"]), int(d["commercio_marittimo"]), int(d["importazioni"])]
	parts.add_theme_color_override("font_color", UiTheme.INK_TITLE)
	inner.add_child(parts)
	var ports: Array = d.get("porti", [])
	var shown := mini(ports.size(), 12)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	inner.add_child(grid)
	for i in shown:
		var port: Dictionary = ports[i]
		var shield := UiTheme.shield(str(port["fazione"]), Vector2(14, 16))
		shield.tooltip_text = str(port["fazione_nome"])
		grid.add_child(shield)
		var name := Label.new()
		name.text = str(port["nome"])
		name.custom_minimum_size.x = 150
		name.clip_text = true
		name.tooltip_text = "%s · %s" % [str(port["fazione_nome"]), str(port["ricchezza"])]
		grid.add_child(name)
		var wealth := Label.new()
		wealth.text = str(port["ricchezza"])
		wealth.custom_minimum_size.x = 84
		wealth.add_theme_font_size_override("font_size", 14)
		wealth.add_theme_color_override("font_color", UiTheme.INK_GOOD if float(port["peso"]) >= 0.8 else UiTheme.INK_FAINT)
		grid.add_child(wealth)
		var gain := Label.new()
		gain.text = "+%d" % int(port["denari"])
		gain.custom_minimum_size.x = 52
		gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(gain)
	if shown % 2 == 1:
		for k in 4:
			grid.add_child(Control.new())
	if ports.size() > shown:
		var rest := 0
		for i in range(shown, ports.size()):
			rest += int((ports[i] as Dictionary)["denari"])
		var more := Label.new()
		more.text = Lang.t("e altri %d porti: +%d") % [ports.size() - shown, rest]
		more.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		inner.add_child(more)
	var hint := Label.new()
	hint.text = Lang.t("Ogni porto compra le merci che non ha e vende le sue: un porto ricco e sviluppato rende molto, uno povero poco.")
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(hint)
	return box


func _toggle_summary() -> void:
	if _summary_panel.visible:
		_summary_panel.visible = false
		return
	var label := _summary_panel.find_child("SummaryLabel", true, false) as Label
	label.text = MainScene.summary_from(_data)
	_summary_panel.visible = true


# --- luoghi leggendari (26/11/2026) ----------------------------------------------------------------------------------------


## Pallini dei luoghi gia' scoperti: un luogo si scopre vedendo la sua regione (nebbia di guerra); prima non compare nulla.
func _refresh_sites() -> void:
	if _site_layer == null or _state == null or _state.rules == null or _state.rules.sites.is_empty() or not RegionMap.world:
		if _hud != null:
			_hud.set_sites_button(false, false, "")
		return
	LegendarySiteProcessor.discover_seen(_state, _player_id, _seen)
	var list: Array[Dictionary] = []
	for s in _state.rules.sites.sites:
		if not s.has_position or _state.campaign.region(s.region) == null:
			continue
		if not LegendarySiteProcessor.is_discovered(_state, _player_id, s.id) or not LegendarySites.manifests(s, _state.year):
			continue
		list.append({"id": s.id, "pos": s.position, "categoria": s.category, "simbolo": s.symbol, "nome": s.label(_state.year),
			"in_attesa": CampaignUiSites.has_pending(_state, _player_id, s.id), "inattivo": not LegendarySites.is_active(_state, s)})
	_site_layer.set_sites(list)
	_update_sites_button()


## Bussola della minimappa: apre o chiude insieme i medaglioni di tutti i luoghi leggendari scoperti.
func _toggle_sites_all() -> void:
	_sites_all = not _sites_all
	if _site_layer != null:
		_site_layer.set_show_all(_sites_all)
	_update_sites_button()


func _update_sites_button() -> void:
	if _hud == null or _site_layer == null:
		return
	var tip := Lang.t("Luoghi leggendari scoperti: %d") % _site_layer.site_count()
	tip += "\n" + (Lang.t("Clic: torna ai pallini") if _sites_all else Lang.t("Clic: mostra i medaglioni di tutti i luoghi scoperti"))
	_hud.set_sites_button(true, _sites_all, tip)


## Scheda del luogo (clic sul pallino o sul medaglione): tavola dipinta, descrizione, effetti, eventi.
func _show_site_sheet(site_id: String) -> void:
	var s := _state.rules.sites.site(site_id)
	if s == null:
		return
	GameAudio.play_sfx("seleziona")
	_hide_hover()
	if _site_panel == null:
		var holder := CenterContainer.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.z_index = 9
		_ui.add_child(holder)
		_site_panel = PanelContainer.new()
		holder.add_child(_site_panel)
		_stack_sheet(holder, _site_panel)
		# il luogo resta in evidenza sulla mappa finche' la scheda e' aperta (28/11/2026)
		_site_panel.visibility_changed.connect(func() -> void:
			if _site_layer != null and not _site_panel.visible:
				_site_layer.set_selected(""))
		var margin := _margin()
		_site_panel.add_child(margin)
		_site_box = VBoxContainer.new()
		_site_box.custom_minimum_size = Vector2(560, 0)
		_site_box.add_theme_constant_override("separation", 8)
		margin.add_child(_site_box)
	_clear_children(_site_box)
	if _site_layer != null:
		_site_layer.set_selected(site_id)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_site_box.add_child(head)
	var tex := load(SiteLayer.texture_path(s.symbol, s.category)) as Texture2D if ResourceLoader.exists(SiteLayer.texture_path(s.symbol, s.category)) else null
	if tex != null:
		head.add_child(UiTheme.picture(tex, Vector2(56, 56)))
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := Label.new()
	title.text = s.label(_state.year)
	title.theme_type_variation = "Title"
	titles.add_child(title)
	var sub := Label.new()
	sub.text = "%s · %s" % [CampaignUiSites.category_label(s.category), CampaignUiText.region_name(_state, s.region)]
	sub.theme_type_variation = "Subtitle"
	titles.add_child(sub)
	var close := _make_button(Lang.t("Chiudi (Esc)"))
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(func() -> void: _site_panel.visible = false)
	head.add_child(close)
	_site_box.add_child(UiTheme.divider())
	var pic := CampaignUiSites.picture(s.id)
	if pic != null:
		_site_box.add_child(UiTheme.picture(pic, Vector2(560, 315)))
	var desc := Label.new()
	desc.text = s.text()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(560, 0)
	_site_box.add_child(desc)
	var holder_line := CampaignUiSites.holder_line(_state, s)
	if not LegendarySites.is_active(_state, s):
		holder_line += " · " + Lang.t("Il luogo non ha piu' effetti")
	if holder_line != "":
		var who := Label.new()
		who.text = holder_line
		who.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		_site_box.add_child(who)
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.custom_minimum_size = Vector2(560, 0)
	rich.add_theme_color_override("default_color", UiTheme.INK)
	var parts := PackedStringArray()
	for sec in CampaignUiSites.sheet_sections(_state, s):
		parts.append("[b]%s[/b]" % str(sec["titolo"]))
		for l in sec["righe"]:
			parts.append(CampaignUiSites.colored(l))
	var events := CampaignUiSites.event_lines(_state, s, _player_id)
	if not events.is_empty():
		parts.append("[b]%s[/b]" % Lang.t("Eventi"))
		parts.append_array(events)
	rich.text = "\n".join(parts)
	_site_box.add_child(rich)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_site_box.add_child(buttons)
	var go := _make_button(Lang.t("Vai alla regione"))
	go.pressed.connect(func() -> void:
		_site_panel.visible = false
		if _anchors.has(s.region):
			_camera.position = s.position
			_clamp_camera()
		var region := _state.campaign.region(s.region)
		if region != null and not region.is_sea:
			_select(region))
	buttons.add_child(go)
	for c in LegendarySiteProcessor.choices_for(_state, _player_id):
		if str(c["luogo"]) == s.id:
			var decide := _make_button(Lang.t("Decidi"))
			var cid := int(c["id"])
			decide.pressed.connect(func() -> void:
				_site_panel.visible = false
				_open_site_choice(cid))
			buttons.add_child(decide)
			break
	_site_panel.visible = true


## Finestra di una scelta di un luogo (come i prigionieri, ADR-073): un pulsante per opzione con costo, requisiti ed esiti;
## «Decidi dopo» la lascia in attesa (a fine anno si sceglie da sola l'opzione piu' prudente).
func _build_site_choice_panel() -> void:
	var modal := IllustratedModal.new()
	modal.set_width(680.0)
	_site_choice_panel = modal
	_site_choice_panel.visible = false
	_site_choice_panel.z_index = 6
	_site_choice_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_site_choice_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_site_choice_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_site_choice_panel)
	_stack_sheet(_site_choice_panel)
	var box := modal.body
	_site_choice_title = Label.new()
	_site_choice_title.add_theme_font_size_override("font_size", 20)
	_site_choice_title.add_theme_color_override("font_color", SECTION_COLOR)
	_site_choice_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_site_choice_title.custom_minimum_size = Vector2(560.0, 0.0)
	box.add_child(_site_choice_title)
	_site_choice_text = Label.new()
	_site_choice_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_site_choice_text.custom_minimum_size = Vector2(560.0, 0.0)
	box.add_child(_site_choice_text)
	_site_choice_list = VBoxContainer.new()
	_site_choice_list.add_theme_constant_override("separation", 6)
	box.add_child(_site_choice_list)


## Mostra la prossima scelta dei luoghi in attesa; falso se non ce ne sono.
func _show_next_site_choice() -> bool:
	while not _site_choice_queue.is_empty():
		var cid: int = _site_choice_queue.pop_front()
		if _open_site_choice(cid):
			return true
	if _site_choice_panel != null:
		_site_choice_panel.visible = false
	return false


func _open_site_choice(choice_id: int) -> bool:
	var w := CampaignUiSites.choice_window(_state, _player_id, choice_id)
	if w.is_empty():
		return false
	_site_choice_current = choice_id
	_site_choice_title.text = str(w["titolo"])
	_site_choice_text.text = str(w["testo"])
	_clear_children(_site_choice_list)
	var options: Array = w["opzioni"]
	for i in options.size():
		var o: Dictionary = options[i]
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		_site_choice_list.add_child(row)
		var b := _make_button(str(o["testo"]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var problem := str(o["problema"])
		b.disabled = problem != ""
		b.tooltip_text = problem if problem != "" else str(o["nota"])
		b.pressed.connect(_on_site_choice.bind(i))
		row.add_child(b)
		var note := Label.new()
		note.text = ("%s (%s)" % [str(o["nota"]), problem]) if problem != "" else str(o["nota"])
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(560.0, 0.0)
		note.add_theme_font_size_override("font_size", 13)
		note.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		row.add_child(note)
	var later := _make_button(Lang.t("Decidi dopo"))
	later.pressed.connect(func() -> void:
		_site_choice_current = 0
		_site_choice_panel.visible = false
		_show_next_popup())
	_site_choice_list.add_child(later)
	var modal := _site_choice_panel as IllustratedModal
	modal.set_category(str(w["categoria"]))
	var pic := CampaignUiSites.picture(str(w["luogo_leggendario"]))
	modal.set_picture(pic if pic != null else EventArt.historical_texture(-1, "luogo_" + str(w["luogo_leggendario"])))
	_site_choice_panel.visible = true
	return true


func _on_site_choice(index: int) -> void:
	if _site_choice_current == 0:
		return
	var result := GameCommands.choose_site_option(_state, _player_id, _site_choice_current, index)
	if not bool(result["ok"]):
		_toast_show(str(result["errore"]))
		return
	var lines: PackedStringArray = result["righe"]
	_toast_show("\n".join(lines) if not lines.is_empty() else Lang.t("Non succede nulla."))
	_site_choice_current = 0
	_site_choice_panel.visible = false
	_refresh_all()
	_show_next_popup()
