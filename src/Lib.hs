{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Lib where

import Control.Concurrent (forkIO, myThreadId, threadDelay)
import qualified Control.Exception as E
import Control.Monad (Monad, forever, unless)
import Control.Monad.Trans (liftIO)
import Data.Aeson (FromJSON (parseJSON), KeyValue ((.=)), ToJSON (toJSON), decode, object, withObject, (.:))
import Data.Aeson.Text (encodeToLazyText)
import Data.Maybe (fromJust)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Data.Text.Lazy (fromStrict, toStrict)
import qualified Data.Text.Lazy.Encoding as T
import Network.Socket (withSocketsDo)
import Network.WebSockets (Connection)
import qualified Network.WebSockets as WS
import Pipes (Consumer, MonadIO (liftIO), Pipe, Producer, await, lift, runEffect, yield, (>->), (>~), (~>))
import Pipes.Concurrent
  ( forkIO,
    fromInput,
    performGC,
    spawn,
    toOutput,
    unbounded,
  )
import Pipes.Core (Consumer, Pipe, Producer, runEffect, (>~>))
import System.Exit
import System.Posix.Signals

data SubscriptionMessage = SubscriptionMessage
  { smId :: Text,
    smCommand :: Text,
    smStreams :: [Text]
  }
  deriving (Show)

data LedgerSubscriptionMessage = LedgerSubscriptionMessage
  { lsmFeeBase :: Int,
    lsmFeeRef :: Int,
    lsmLedgerHash :: Text,
    lsmLedgerIndex :: Int,
    lsmLedgerTime :: Int,
    lsmReserveBase :: Int,
    lsmReserveInc :: Int,
    lsmTxnCount :: Int,
    lsmType :: Text,
    lsmValidatedLedgers :: Text
  }
  deriving (Show)

instance FromJSON LedgerSubscriptionMessage where
  parseJSON = withObject "ledger_subscription_message" $ \o -> do
    lsmFeeBase <- o .: "fee_base"
    lsmFeeRef <- o .: "fee_ref"
    lsmLedgerHash <- o .: "ledger_hash"
    lsmLedgerIndex <- o .: "ledger_index"
    lsmLedgerTime <- o .: "ledger_time"
    lsmReserveBase <- o .: "reserve_base"
    lsmReserveInc <- o .: "reserve_inc"
    lsmTxnCount <- o .: "txn_count"
    lsmType <- o .: "type"
    lsmValidatedLedgers <- o .: "validated_ledgers"
    return LedgerSubscriptionMessage {..}

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
  resp :: Text <- WS.receiveData conn
  return ()

wsClientProducer :: Connection -> Producer Text IO ()
wsClientProducer conn =
  forever $ do
    msg <- liftIO $ WS.receiveData conn
    yield msg

wsClientMessageTransformer :: Pipe Text LedgerSubscriptionMessage IO ()
wsClientMessageTransformer = forever $ do
  msg <- await
  let ledger = fromJust $ decode $ T.encodeUtf8 $ fromStrict msg :: LedgerSubscriptionMessage
  yield ledger

wsClientConsumer :: Consumer LedgerSubscriptionMessage IO ()
wsClientConsumer = forever $ do
  msg <- await
  do liftIO $ putStrLn $ "Received block: " <> show msg

wsClientProcessor :: Consumer LedgerSubscriptionMessage IO ()
wsClientProcessor = forever $ do
  msg <- await
  lift $ threadDelay 5000000
  do liftIO $ putStrLn $ "Processed block: " <> show (lsmLedgerIndex msg)

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
  forkIO $
    do runEffect $ wsClientProducer conn >-> wsClientMessageTransformer >-> toOutput (inboundOutput <> processorOutput)
  performGC
  forkIO $
    do runEffect $ fromInput processorInput >-> wsClientProcessor
  performGC

  -- Run our websocket client pipeline
  runEffect $ fromInput inboundInput >-> wsClientConsumer

  putStrLn ("Disconnecting from: " <> host)
  WS.sendClose conn ("Disconnecting" :: Text)

wsClientRun :: String -> Int -> IO ()
wsClientRun host port = withSocketsDo $ WS.runClient host port "/" (wsClient host port)