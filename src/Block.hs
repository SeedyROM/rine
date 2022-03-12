{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Block where

import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import Data.Aeson (FromJSON, decode, withObject, (.:))
import Data.Aeson.Types (FromJSON (parseJSON))
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.Text.Lazy (fromStrict)
import qualified Data.Text.Lazy.Encoding as T
import Pipes
  ( Consumer,
    MonadIO (liftIO),
    MonadTrans (lift),
    Pipe,
    await,
    yield,
  )

data Ledger = Ledger
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

instance FromJSON Ledger where
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
    return Ledger {..}

blockTransformer :: Monad m => Pipe Text Ledger m r
blockTransformer = forever $ do
  msg <- await
  let ledger = fromJust $ decode $ T.encodeUtf8 $ fromStrict msg :: Ledger
  yield ledger

blockFoundInfo :: (Monad m, MonadIO m) => Consumer Ledger m r
blockFoundInfo = forever $ do
  msg <- await
  liftIO $ putStrLn $ "Received block: " <> show msg

blockProcessor :: Consumer Ledger IO ()
blockProcessor = forever $ do
  msg <- await
  lift $ threadDelay 3000000
  do liftIO $ putStrLn $ "Processed block: " <> show (lsmLedgerIndex msg)