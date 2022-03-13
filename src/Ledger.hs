{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Ledger where

import Control.Monad (forever)
import qualified Control.Monad as Data.Foldable
import Data.Aeson
  ( FromJSON,
    KeyValue ((.=)),
    ToJSON,
    decode,
    eitherDecode,
    encode,
    object,
    withObject,
    (.:),
  )
import Data.Aeson.Types (FromJSON (parseJSON), ToJSON (toJSON))
import Data.Cache.LRU.IO as LRU (AtomicLRU, lookup)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text.Lazy (fromStrict)
import qualified Data.Text.Lazy.Encoding as T
import qualified Network.WebSockets as WS
import Pipes
  ( Consumer,
    MonadIO (liftIO),
    Pipe,
    await,
    yield,
  )
import System.Log.Logger (debugM, errorM, infoM)
import System.Timeout (timeout)
import Transaction (FullLedger)
import Util (WSApiResponse (wsarResult), WSApiResponseData (wsardLedger), wsClientRun)

-- | A XRP ledger object we get back from a subscription
data Ledger = Ledger
  { lFeeBase :: Int,
    lFeeRef :: Int,
    lLedgerHash :: Text,
    lLedgerIndex :: Int,
    lLedgerTime :: Int,
    lReserveBase :: Int,
    lReserveInc :: Int,
    lTxnCount :: Int,
    lType :: Text,
    lValidatedLedgers :: Text
  }
  deriving (Show)

instance FromJSON Ledger where
  parseJSON = withObject "ledger" $ \o -> do
    lFeeBase <- o .: "fee_base"
    lFeeRef <- o .: "fee_ref"
    lLedgerHash <- o .: "ledger_hash"
    lLedgerIndex <- o .: "ledger_index"
    lLedgerTime <- o .: "ledger_time"
    lReserveBase <- o .: "reserve_base"
    lReserveInc <- o .: "reserve_inc"
    lTxnCount <- o .: "txn_count"
    lType <- o .: "type"
    lValidatedLedgers <- o .: "validated_ledgers"
    return Ledger {..}

-- | Message to find a ledger and get all it's data
data LedgerFetchByIndex = LedgerFetchByIndex
  { lfbiId :: Int,
    lfbiLedgerIndex :: Int,
    lfbiCommand :: Text,
    lfbiTransactions :: Bool,
    lfbiExpand :: Bool
  }

instance ToJSON LedgerFetchByIndex where
  toJSON lfbi =
    object
      [ "id" .= lfbiId lfbi,
        "ledger_index" .= lfbiLedgerIndex lfbi,
        "command" .= lfbiCommand lfbi,
        "transactions" .= lfbiTransactions lfbi,
        "expand" .= lfbiExpand lfbi
      ]

instance FromJSON LedgerFetchByIndex where
  parseJSON = withObject "ledger_fetch_by_index" $ \o -> do
    lfbiId <- o .: "id"
    lfbiLedgerIndex <- o .: "ledger_index"
    lfbiCommand <- o .: "command"
    lfbiTransactions <- o .: "transactions"
    lfbiExpand <- o .: "expand"
    return LedgerFetchByIndex {..}

-- | Convert the ledger JSON into a `Ledger`
ledgerTransformer :: Monad m => Pipe Text Ledger m r
ledgerTransformer = forever $ do
  msg <- await
  let ledger = decode $ T.encodeUtf8 $ fromStrict msg :: Maybe Ledger
  Data.Foldable.forM_ ledger yield -- Interesting, this handles Nothings by doing... nothing?

-- | Print info about the received ledger
ledgerFoundInfo :: (Monad m, MonadIO m) => AtomicLRU Int Ledger -> Consumer Ledger m r
ledgerFoundInfo cache = forever $ do
  msg <- await
  liftIO $ do
    exists <- LRU.lookup (lLedgerIndex msg) cache
    infoM "Ledger" ("Received ledger: " <> show (lLedgerIndex msg))
    infoM "Ledger" ("Has processed ledger this run: " <> show (isJust exists))
    debugM "Ledger" ("Received ledger data: " <> show msg)

-- TODO: This needs to be greedy workers not in order

-- | Consumer to take in ledgers and get data from a websocket
ledgerProcessor :: (Monad m, MonadIO m) => String -> Int -> Consumer Ledger m r
ledgerProcessor host port = forever $ do
  msg <- await
  liftIO $ do
    result <- timeout 20000000 $ wsClientRun host port $ ledgerGetLedgerData $ lLedgerIndex msg
    case result of
      Just ledger -> liftIO $ do
        infoM "Ledger" ("Processed ledger: " <> show (lLedgerIndex msg))
        debugM "Ledger" ("Processed ledger data: " <> show ledger)
      Nothing -> liftIO $ do
        errorM "Ledger" ("Failed to retrieve ledger: " <> show (lLedgerIndex msg))

-- | Use a websocket connection to get a ledger
ledgerGetLedgerData :: Int -> WS.ClientApp (Maybe FullLedger)
ledgerGetLedgerData ledgerIndex conn = do
  -- Await a message
  _ <- liftIO $ WS.sendTextData conn $ encode $ LedgerFetchByIndex 1 ledgerIndex "ledger" True True
  value :: Text <- WS.receiveData conn

  -- Parse the response
  let response = eitherDecode $ T.encodeUtf8 $ fromStrict value :: Either String (WSApiResponse FullLedger)
  -- Handle errors or return
  case response of
    Left e -> liftIO $ do
      errorM "Ledger" e
      WS.sendClose conn ("Bye bye" :: Text)
      return Nothing
    Right r -> liftIO $ do
      let ledger = wsardLedger $ wsarResult r
      debugM "Ledger" ("Retrieved ledger: " <> show ledger)
      WS.sendClose conn ("Bye bye" :: Text)
      return ledger
