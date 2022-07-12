{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Model where

import Control.Concurrent.STM
import Data.Text

newtype State s = State
  { psState :: TVar s
  }

newtype Msg a = Msg a

data Pipeline a = Pipeline
  { pName :: Text,
    pInlets :: [Pipeline a],
    pOutlets :: [Pipeline a]
  }
  deriving (Show, Functor, Foldable, Traversable)

