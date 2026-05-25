# Websocket Streaming

Connect to: `wss://localhost:5100/v1/api/ws`

## Subscribe to market data

Send: `smd+CONID+{"fields":["31","84","86"]}`

Example: `smd+265598+{"fields":["31","84","85","86","88","7059"]}`

## Subscribe to chart data

Send: `smh+CONID+{"period":"1d","bar":"5min","outsideRth":false}`

## Unsubscribe

Send: `umd+CONID` (market data) or `umh+CONID` (chart data)

## Streaming behavior

- During regular trading hours with websocket: ticks every **250ms**
- Without websocket or disconnected: ticks every **3 seconds**
- Chart data updates every **1 minute**
