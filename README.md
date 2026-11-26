# Medieval Quest

Gioco di strategia a turni, per un solo giocatore, sulla mappa del mondo dal 1000 al 1700. È ispirato alla campagna di **Medieval: Total War** (con la mod XL 3.0): stessi meccanismi di dinastie, emissari, spie, crociate, Papato ed eventi storici, ma senza battaglie 3D. Scontri e assedi si risolvono in automatico e tutto si gioca sulla plancia.

Il gioco è scritto da zero con [Godot Engine 4.7](https://godotengine.org) (GDScript). Non serve avere installato il gioco originale.

> **Progetto amatoriale e open, senza supporto.** Il codice è sotto licenza MIT (vedi [LICENSE](LICENSE)). Non ci sono garanzie, assistenza, aggiornamenti programmati né tempi di risposta: issue e richieste possono restare senza risposta. Usalo così com'è.

## Scaricare e installare

1. Apri la pagina [Releases](../../releases) e scarica l'ultimo `MedievalQuest-Setup-<versione>.exe`.
2. Avvia l'installer. Non servono diritti di amministratore: di default il gioco va in `%LOCALAPPDATA%\Programs\Medieval Quest`.
3. Avvia **Medieval Quest** dal menu Start o dal collegamento sul desktop.

Windows può mostrare l'avviso di SmartScreen perché l'installer non è firmato: «Ulteriori informazioni» → «Esegui comunque».

**Requisiti:** Windows 10 o 11 a 64 bit, scheda video compatibile con Vulkan o OpenGL 3.3 (va bene anche una grafica integrata recente), circa 1 GB di spazio libero.

**Salvataggi e impostazioni** stanno in `%APPDATA%\Godot\app_userdata\MTW Remake`. La disinstallazione non li cancella.

## Come si gioca

La guida completa, con comandi e regole principali, è in [docs/GUIDA_DI_GIOCO.md](docs/GUIDA_DI_GIOCO.md); l'installer la copia anche nella cartella del gioco. In partita il tasto **H** mostra l'elenco dei comandi.

## Diritti e crediti

*Medieval: Total War* e *Total War* sono marchi e opere dei rispettivi titolari (The Creative Assembly / SEGA; il gioco originale è stato pubblicato da Activision nel 2002). Medieval Quest è un progetto di fan **non ufficiale**, senza scopo di lucro, non affiliato né approvato da loro. Il gioco non contiene file dell'originale: immagini, musiche ed effetti sono nuovi o da librerie libere. I dati della campagna (province, fazioni, unità, edifici, nomi) derivano da quelli dell'originale e della mod XL.

Dettagli, crediti di caratteri, motore e immagini in [CREDITI_E_DIRITTI.md](CREDITI_E_DIRITTI.md).

## Per chi vuole modificarlo

Codice, dati e strumenti sono in questo repository. Come aprire il progetto, eseguire i test e ricostruire eseguibile e installer è spiegato in [docs/SVILUPPO.md](docs/SVILUPPO.md).

---

*English summary:* Medieval Quest is a free, unofficial, single-player turn-based strategy game (1000–1700, world map) inspired by the campaign of Medieval: Total War, rebuilt from scratch in Godot. Code is MIT-licensed; it contains no files from the original game (images, music and sounds are new or from free libraries), while campaign data is derived from the original game and the XL mod. Provided as is, with **no support**. Not affiliated with The Creative Assembly, SEGA or Activision.
