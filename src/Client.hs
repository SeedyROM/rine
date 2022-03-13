module Client where

import Websockets.Util (wsClientRun)
import Websockets.WSClient (wsClient)

-- | Start the websocket pipeline
-- TODO: This could be curried?
clientRun :: String -> Int -> IO ()
clientRun host port = wsClientRun host port $ wsClient host port