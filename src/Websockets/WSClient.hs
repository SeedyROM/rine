{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Websockets.WSClient where

import Control.Concurrent (forkIO)
import Control.Monad (forever)
import Control.Monad.Trans (liftIO)
import Data.Aeson (KeyValue ((.=)), ToJSON (toJSON), object)
import Data.Aeson.Text (encodeToLazyText)
import Data.Cache.LRU.IO (AtomicLRU, newAtomicLRU)
import Data.Text (Text)
import Data.Text.Lazy (toStrict)
import Domain.Ledger
import Network.WebSockets (Connection)
import qualified Network.WebSockets as WS
import Pipeline.Ledger (ledgerFoundInfo, ledgerProcessor, ledgerTransformer)
import Pipes (MonadIO, Producer, runEffect, yield, (>->))
import Pipes.Concurrent
  ( fromInput,
    spawn,
    toOutput,
    unbounded,
  )
import System.Log.Logger (infoM)

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

-- | Helper
toText :: ToJSON a => a -> Text
toText = toStrict . encodeToLazyText

-- | Build a subscription message to listen for ledgers
wsSubscriptionMessage :: Text
wsSubscriptionMessage = toText $ SubscriptionMessage {smId = "Listen for ledger", smCommand = "subscribe", smStreams = ["ledger"]}

-- | Send a subscription message
wsSubscribe :: WS.ClientApp ()
wsSubscribe conn = do
  infoM "WSClient" "Sending subscription"
  WS.sendTextData conn wsSubscriptionMessage

-- | Eat the response from the subscription
wsHandleResponse :: (Monad m, MonadIO m) => Connection -> m ()
wsHandleResponse conn = do
  _resp :: Text <- liftIO $ WS.receiveData conn
  return ()

-- | Receive incoming data from the websocket and produce it as text into the pipeline
wsClientProducer :: (Monad m, MonadIO m) => Connection -> Producer Text m r
wsClientProducer conn =
  forever $ do
    msg <- liftIO $ WS.receiveData conn
    yield msg

-- | Where the magic happens
wsClient :: String -> Int -> WS.ClientApp ()
wsClient host port conn = do
  infoM "WSClient" ("Connected to: " <> host)

  -- Send subscription
  wsSubscribe conn
  wsHandleResponse conn

  -- LRU Cache for blocks
  cache <- newAtomicLRU (Just 1024) :: IO (AtomicLRU Int Ledger)

  -- Fancy pipes stuff
  (inboundOutput, inboundInput) <- spawn unbounded
  (processorOutput, processorInput) <- spawn unbounded

  -- Spawn our tasks
  _ <- forkIO $
    do runEffect $ wsClientProducer conn >-> ledgerTransformer >-> toOutput (inboundOutput <> processorOutput)
  _ <- forkIO $
    do runEffect $ fromInput processorInput >-> ledgerProcessor host port

  -- Run our websocket client pipeline
  runEffect $ fromInput inboundInput >-> ledgerFoundInfo cache

  -- TODO: This is never reached, not sure how to handle cleanup
  infoM "WSClient" ("Disconnecting from: " <> host)
  WS.sendClose conn ("Disconnecting" :: Text)
