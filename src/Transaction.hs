{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS_GHC -Wno-missing-fields #-}

module Transaction where

import Data.Aeson (FromJSON (parseJSON), withObject, (.:), (.:?))
import Data.Text (Text)

type Addr = Text

type Flags = Int

data FullLedger = FullLedger
  { flAccepted :: Bool,
    flAccountHash :: Addr,
    flCloseFlags :: Flags,
    flCloseTime :: Int,
    flCloseTimeResolution :: Int,
    flClosed :: Bool,
    flHash :: Text,
    flLedgerHash :: Text,
    flLedgerIndex :: Text,
    flParentCloseTime :: Int,
    flParentHash :: Text,
    flSeqNum :: Text,
    flTotalCoins :: Text,
    flTransactionHash :: Text,
    flTransactions :: [Transaction]
  }
  deriving (Show)

instance FromJSON FullLedger where
  parseJSON = withObject "full_ledger" $ \o -> do
    flAccepted <- o .: "accepted"
    flAccountHash <- o .: "account_hash"
    flCloseFlags <- o .: "close_flags"
    flCloseTime <- o .: "close_time"
    flCloseTimeResolution <- o .: "close_time_resolution"
    flClosed <- o .: "closed"
    flHash <- o .: "hash"
    flLedgerHash <- o .: "ledger_hash"
    flLedgerIndex <- o .: "ledger_index"
    flParentCloseTime <- o .: "parent_close_time"
    flParentHash <- o .: "parent_hash"
    flSeqNum <- o .: "seqNum"
    flTotalCoins <- o .: "total_coins"
    flTransactionHash <- o .: "transaction_hash"
    flTransactions <- o .: "transactions"
    return FullLedger {..}

data TransactionLimitAmount = TransactionLimitAmount
  { tlaCurrency :: Maybe Text,
    tlaIssuer :: Maybe Addr,
    tlaValue :: Text
  }
  deriving (Show)

instance FromJSON TransactionLimitAmount where
  parseJSON = withObject "transaction_limit_amount" $ \o -> do
    tlaCurrency <- o .:? "currency"
    tlaIssuer <- o .:? "issuer"
    tlaValue <- o .: "value"
    return TransactionLimitAmount {..}

data Transaction = Transaction
  { tTransactionIndex :: Maybe Integer,
    tTransactionResult :: Maybe String,
    tHash :: Text,
    tAccount :: Addr,
    tFee :: Text,
    tFlags :: Maybe Flags,
    tLastLedgerSequence :: Maybe Integer,
    tLimitAmount :: Maybe TransactionLimitAmount,
    tSequence :: Integer,
    tSigningPubKey :: Text,
    tTransactionType :: Text,
    tTxnSignature :: Maybe Text
  }
  deriving (Show)

instance FromJSON Transaction where
  parseJSON = withObject "transaction" $ \o -> do
    tTransactionIndex <- o .:? "TransactionIndex"
    tTransactionResult <- o .:? "TransactionResult"
    tHash <- o .: "hash"
    tAccount <- o .: "Account"
    tFee <- o .: "Fee"
    tFlags <- o .:? "Flags"
    tLastLedgerSequence <- o .:? "LastLedgerSequence"
    tLimitAmount <- o .:? "LimitAmount"
    tSequence <- o .: "Sequence"
    tSigningPubKey <- o .: "SigningPubKey"
    tTransactionType <- o .: "TransactionType"
    tTxnSignature <- o .:? "TxnSignature"
    return Transaction {..}
