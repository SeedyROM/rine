module Main where

import Lib (wsClientRun)

main :: IO ()
main = wsClientRun "s2.ripple.com" 443
