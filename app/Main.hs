module Main where

import Env (bootstrapEnv)
import Lib (clientRun)

main :: IO ()
main = do
  bootstrapEnv $ do
    clientRun "s2.ripple.com" 443
