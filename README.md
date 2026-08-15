# Walfin Money Printer

Expert Advisor MetaTrader 5 — **BOS Reversal + Mean Reversion** (v3.70)

Stratégie de trading multi-symboles (EURUSD, XAUUSD, GBPJPY, USDJPY) combinant :
- **BOS (Break of Structure)** : cassures de structure via ZigZag/swings, confirmées par FVG, momentum, range asiatique et liquidity sweep.
- **Mean Reversion** : signaux sur bandes de Bollinger + RSI en régime à faible ADX.
- **Gestion du risque** : 1,5 %/trade, arrêt 3 %/jour, stop après 3 pertes, mode recovery, Kelly criterion et risk parity.
- **Dashboard visuel** temps réel.

## Fichier principal
- `BosReversalEA.mq5` — code source complet de l'EA.

## Installation
1. Copier `BosReversalEA.mq5` dans `MQL5/Experts/`.
2. Compiler dans MetaEditor (`F7`).
3. Attacher l'EA à un graphique et configurer les inputs.

## Avertissement
Le trading comporte des risques importants. Outil fourni à titre éducatif, sans conseil en investissement.
