module Util where

import Network.Socket (withSocketsDo)
import qualified Network.WebSockets as WS

wsClientRun :: String -> Int -> WS.ClientApp a -> IO a
wsClientRun host port = withSocketsDo . WS.runClient host port "/"