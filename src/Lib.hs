module Lib where

import Util (wsClientRun)
import WSClient (wsClient)

clientRun :: String -> Int -> IO ()
clientRun host port = wsClientRun host port (wsClient host port)