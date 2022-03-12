{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module WSClient where

import Control.Concurrent (forkIO)
import Control.Monad (forever)
import Control.Monad.Trans (liftIO)
import Data.Aeson (KeyValue ((.=)), ToJSON (toJSON), object)
import Data.Aeson.Text (encodeToLazyText)
import Data.Text (Text)
import qualified Data.Text.IO as T
import Data.Text.Lazy (toStrict)
import Ledger (ledgerFoundInfo, ledgerProcessor, ledgerTransformer)
import Network.WebSockets (Connection)
import qualified Network.WebSockets as WS
import Pipes (Producer, runEffect, yield, (>->))
import Pipes.Concurrent
  ( fromInput,
    spawn,
    toOutput,
    unbounded,
  )

data SubscriptionMessage = SubscriptionMessage
  { smId :: Text,
    smCommand :: Text,
    smStreams :: [Text]
  }
  deriving (Show)

instance ToJSON SubscriptionMessage where
  toJSON sm =
    object
      [ "id" .= smId sm,
        "command" .= smCommand sm,
        "streams" .= smStreams sm
      ]

toText :: ToJSON a => a -> Text
toText = toStrict . encodeToLazyText

wsSubscriptionMessage :: Text
wsSubscriptionMessage = toText $ SubscriptionMessage {smId = "Listen for ledger", smCommand = "subscribe", smStreams = ["ledger"]}

wsSubscribe :: WS.ClientApp ()
wsSubscribe conn = do
  T.putStrLn "Sending subscription"
  WS.sendTextData conn wsSubscriptionMessage

wsHandleResponse :: WS.ClientApp ()
wsHandleResponse conn = do
  _resp :: Text <- WS.receiveData conn
  return ()

wsClientProducer :: Connection -> Producer Text IO ()
wsClientProducer conn =
  forever $ do
    msg <- liftIO $ WS.receiveData conn
    yield msg

wsClient :: String -> Int -> WS.ClientApp ()
wsClient host port conn = do
  putStrLn ("Connected to: " <> host)

  -- Send subscription
  wsSubscribe conn
  wsHandleResponse conn

  -- Fancy pipes stuff
  (inboundOutput, inboundInput) <- spawn unbounded
  (processorOutput, processorInput) <- spawn unbounded

  -- Spawn our tasks
  _ <- forkIO $
    do runEffect $ wsClientProducer conn >-> ledgerTransformer >-> toOutput (inboundOutput <> processorOutput)
  _ <- forkIO $
    do runEffect $ fromInput processorInput >-> ledgerProcessor host port

  -- Run our websocket client pipeline
  runEffect $ fromInput inboundInput >-> ledgerFoundInfo

  -- TODO: This is never reached, not sure how to handle cleanup
  putStrLn ("Disconnecting from: " <> host)
  WS.sendClose conn ("Disconnecting" :: Text)
