module Main where

import Client (clientRun)
import System.Env (bootstrapEnv)

main :: IO ()
main = do
  bootstrapEnv $ do
    clientRun "s2.ripple.com" 443
