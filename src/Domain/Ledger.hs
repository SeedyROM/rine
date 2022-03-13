{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Domain.Ledger where

import Data.Aeson
  ( FromJSON,
    KeyValue ((.=)),
    ToJSON,
    object,
    withObject,
    (.:),
  )
import Data.Aeson.Types (FromJSON (parseJSON), ToJSON (toJSON))
import Data.Text (Text)

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
