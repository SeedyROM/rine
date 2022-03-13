module Util where

import Network.Socket (withSocketsDo)
import qualified Network.WebSockets as WS

-- | Start a websocket client with curried WS.ClientApp
wsClientRun :: String -> Int -> WS.ClientApp a -> IO a
wsClientRun host port = withSocketsDo . WS.runClient host port "/"
