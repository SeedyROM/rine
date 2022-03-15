-- This is needed for our priority conversion, somehow it thinks the constructors are giant strings lol.
{-# OPTIONS_GHC -Wno-incomplete-patterns #-}

module System.Env where

import System.Envy (FromEnv (fromEnv), decodeEnv, envMaybe, (.!=))
import System.IO (stdout)
import System.Log.Formatter (simpleLogFormatter)
import System.Log.Handler (LogHandler (setFormatter))
import System.Log.Handler.Simple (streamHandler)
import System.Log.Logger (Priority (..), emergencyM, rootLoggerName, setHandlers, setLevel, updateGlobalLogger)

-- | Convert a String into a Logger.Priority constructor
stringToPriority :: String -> Priority
stringToPriority level = case level of
  "debug" -> DEBUG
  "info" -> INFO
  "notice" -> NOTICE
  "warn" -> WARNING
  "error" -> ERROR
  "critical" -> CRITICAL
  "alert" -> ALERT
  "emergency" -> EMERGENCY

-- | Environment configuration
newtype Config = Config
  { configLogLevel :: String
  }
  deriving (Show)

instance FromEnv Config where
  fromEnv _ = Config <$> envMaybe "LOG_LEVEL" .!= "info"

-- | Default formatter string
defaultFormatterString :: String
defaultFormatterString = "[$utcTime - [($tid) $loggername]: $prio] $msg"

-- | Setup our logging environment
setupLogging :: Config -> IO ()
setupLogging config = do
  stdOutHandler <-
    streamHandler stdout level >>= \lh ->
      return $
        setFormatter lh (simpleLogFormatter defaultFormatterString)
  updateGlobalLogger rootLoggerName (setLevel level . setHandlers [stdOutHandler])
  where
    level = stringToPriority $ configLogLevel config

-- | Bootstrap our environment and run f
bootstrapEnv :: IO () -> IO ()
bootstrapEnv f = do
  environment <- decodeEnv :: IO (Either String Config)
  case environment of
    Right config -> do
      setupLogging config
      f
    Left _ -> do
      emergencyM "main" "Failed to load config!"
      return ()
