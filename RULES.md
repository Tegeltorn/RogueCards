# RogueCards – regler för bordet

Spelas solo med en vanlig kortlek (52 kort + 2 jokrar). Allt som behövs är korten.

## Uppställning
1. **Startlek:** de fyra tvåorna (2♥ 2♦ 2♠ 2♣), blandade.
2. **Modess:** blanda de fyra essen och dra ett. Dess färg ger omgångens mod (se nedan). Lägg sedan `lives` av de andra essen framför dig som **liv**.
3. **Temakung:** blanda de fyra kungarna och dra en. Dess färg styr jokrarna.
4. **Bosshög:** de tre andra kungarna plus den svarta jokern. Den röda jokern läggs åt sidan.
5. **Fiender:** valörerna 3 till dam, en hög per valör. På våningarna i `short_floors` blandar du högen och tar bort ett kort, så att tre är kvar.

## Våning och runda
Våningarna går i ordning 3, 4 … 10, knekt, dam och sist kungen. **I början av varje våning** blandas hela leken till en ny dragbunt. Slänghögen töms och sparade kort och sparad sköld nollställs.

Varje runda:
1. **Vänd upp** fiendens översta kort. Svart = attack, rött = sköld. Värdet är valören.
2. **Fyll handen** till `hand_size` kort (`boss_hand_size` mot kungarna). Är dragbunten tom blandar du slänghögen till en ny.
3. **Spela** valfritt antal kort av rätt färg: röda mot attack, svarta mot sköld.
   - **Attack:** räcker ditt block klarar du dig, annars tar du skada. Kortet är besegrat i båda fallen.
   - **Sköld:** räcker din attack är skölden besegrad. Annars läggs kortet sist i fiendens hög.
   - **Låst:** misslyckas du mot en sköld och det inte finns några svarta kort kvar i fiendens hög, förlorar du 1 liv och skölden räknas som besegrad.
4. **Spara** upp till `retain` ospelade kort. Resten och de spelade korten går till slänghögen.

| Färg | Effekt |
|---|---|
| ♥ | Block. Överskottet sparas som sköld **till nästa runda** (högst hjärterkortens summa). Låt hjärtrena ligga kvar som påminnelse. |
| ♦ | Block. Dra 1 kort per ruter du spelar. De dragna korten kan spelas samma runda. |
| ♠ | Attack. Värdet × 1,5, avrundat nedåt (2→3, 3→4, 5→7 …). |
| ♣ | Attack. +`club_pair_bonus` om du spelar minst två klöver samma runda. |

**Skada:** en miss med 1 till `graded_threshold` − 1 kostar 1 liv. En större miss kostar 2 liv. Lägg förlorade ess åt sidan. När inga ess är kvar har du förlorat.

**Essoffer:** när du har minst 2 liv kan du offra ett livs-ess under en runda. Du förlorar livet, och esset räknas som ett kort med värdet 14 i sin egen färg den rundan (rött blockar, svart attackerar).

## Belöning (efter varje våning utom kungens)
Färgen på det **sista besegrade fiendekortet** bestämmer belöningen. Du väljer bland våningens besegrade kort.

| Sista kortet | Belöning |
|---|---|
| ♠ | Välj fritt bland alla besegrade kort. |
| ♣ | Vänd upp 2, ta 1. Ta sedan bort 1 valfritt kort ur leken. |
| ♥ | Få tillbaka ett förlorat liv. Har du alla liv: vänd upp 2 och ta 1. |
| ♦ | Vänd upp 2 och ta båda. |

Har leken färre än `deck_cap` kort måste du lägga till det nya kortet. Är leken full byter du ut ett kort mot det nya, eller avstår. Leken får aldrig bli mindre än `deck_min` kort.

## Jokrar och kungen
| Tema | Röd joker (efter knektvåningen: lägg den under valfritt kort i leken) | Svart joker (i bosshögen) |
|---|---|---|
| ♥ | Kortet räknas som båda färgerna | Den senast besegrade kungen läggs sist i bosshögen |
| ♦ | Kortet hamnar alltid i första handen på varje våning | Sköld 14 |
| ♠ | Kortet har dubbelt värde | Attack 14 |
| ♣ | Dra 2 kort när kortet spelas | Vänd upp de två nästa korten och klara båda med samma hand |

Besegrar du hela bosshögen har du vunnit.

## Mods (modesset)
| Modess | Mod |
|---|---|
| ♥ Härdad | Hjärterbelöningen läker 2 liv, men essoffer är avstängt. |
| ♦ Rik | Välj en extra trea till startleken. Våning 3 består då av de tre andra treorna. Ruterbelöningen ger bara 1 kort. |
| ♠ Blodtörst | Din attack får +1, men varje fiendeattack får också +1. |
| ♣ Förutseende | Du ser de två nästa fiendekorten, men får inte spara kort. |

## Aktuella balansvärden
De här värdena hålls i synk med `config/balance.json` av ett test.

| Nyckel | Värde | Betydelse |
|---|---|---|
| `hand_size` | 4 | Handstorlek |
| `boss_hand_size` | 3 | Handstorlek mot kungarna |
| `retain` | 1 | Kort du får spara mellan rundor |
| `deck_cap` | 9 | Max antal kort i leken |
| `deck_min` | 4 | Min antal kort i leken |
| `lives` | 3 | Antal livs-ess |
| `short_floors` | [3,4,5] | Våningar med bara 3 fiender |
| `graded_threshold` | 5 | Miss som kostar 2 liv |
| `club_pair_bonus` | 2 | Klöverbonus |
