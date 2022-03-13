-- This is needed for our priority conversion, somehow it thinks the constructors are giant strings lol.
{-# OPTIONS_GHC -Wno-incomplete-patterns #-}

module Env where

import System.Envy (FromEnv (fromEnv), decodeEnv, envMaybe, (.!=))
import System.Log.Logger (Priority (..), emergencyM, setLevel, updateGlobalLogger)

stringToPriority :: String -> Priority
stringToPriority level = case level of
  "debug" -> DEBUG
  "info" -> INFO
  "notice" -> NOTICE
  "warning" -> WARNING
  "error" -> ERROR
  "critical" -> CRITICAL
  "alert" -> ALERT
  "emergency" -> EMERGENCY

newtype Configuration = Configuration
  { configLogLevel :: String
  }
  deriving (Show)

instance FromEnv Configuration where
  fromEnv _ = Configuration <$> envMaybe "LOG_LEVEL" .!= "info"

bootstrapEnv :: IO () -> IO ()
bootstrapEnv f = do
  environment <- decodeEnv :: IO (Either String Configuration)
  case environment of
    Right config -> do
      updateGlobalLogger "" (setLevel $ stringToPriority $ configLogLevel config)
      f
    Left _ -> do
      emergencyM "main" "Failed to load configuration!"
      return ()
