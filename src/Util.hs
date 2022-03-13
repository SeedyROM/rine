{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Util where

import Data.Aeson (FromJSON (parseJSON), withObject, (.:))
import Data.Text (Text)
import Network.Socket (withSocketsDo)
import qualified Network.WebSockets as WS

-- | Response from the websocket client
data WSApiResponse a = WSApiResponse
  { wsarId :: Int,
    wsarResult :: Either String a,
    wsarStatus :: Text,
    wsarType :: Text
  }
  deriving (Show)

instance FromJSON a => FromJSON (WSApiResponse a) where
  parseJSON = withObject "response" $ \o -> do
    wsarId <- o .: "id"
    wsarResult <- o .: "result.ledger" -- TODO: This is a hack for now, need to pass the value in somehow
    wsarStatus <- o .: "status"
    wsarType <- o .: "type"
    return WSApiResponse {..}

-- | Start a websocket client with curried WS.ClientApp
wsClientRun :: String -> Int -> WS.ClientApp a -> IO a
wsClientRun host port = withSocketsDo . WS.runClient host port "/"