{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Pipeline.Ledger where

import Control.Monad (forever)
import qualified Control.Monad as Data.Foldable
import Control.Retry (fullJitterBackoff, limitRetries, retrying)
import Data.Aeson
  ( decode,
    eitherDecode,
    encode,
  )
import Data.Cache.LRU.IO as LRU (AtomicLRU, lookup)
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Data.Text.Lazy (fromStrict)
import qualified Data.Text.Lazy.Encoding as T
import Domain.Ledger
import Domain.Transaction (FullLedger)
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
import Websockets.Util (WSApiResponse (wsarResult), WSApiResponseData (wsardLedger), wsClientRun)

-- | Helper to setup a RetryPolicy and retrying for our tasks
ledgerProcessorRetry :: Int -> Int -> Int -> IO a -> IO (Maybe a)
ledgerProcessorRetry backoff limit timeoutAmount f =
  retrying
    (fullJitterBackoff backoff <> limitRetries limit)
    (const $ return . isNothing)
    \_ -> timeout timeoutAmount f

-- | Default retry
defaultLedgerProcessorRetry :: IO a -> IO (Maybe a)
defaultLedgerProcessorRetry = ledgerProcessorRetry 50000 10 10000000

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

-- | Consumer to take in ledgers and get data from a websocket,
-- | also should probably reuse the a websocket connection not make a new one
ledgerProcessor :: (Monad m, MonadIO m) => String -> Int -> Consumer Ledger m r
ledgerProcessor host port = forever $ do
  msg <- await
  liftIO $ do
    result <-
      defaultLedgerProcessorRetry $
        wsClientRun host port $
          ledgerGetLedgerData $
            lLedgerIndex msg
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
