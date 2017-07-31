{-# LANGUAGE TemplateHaskell #-}
module App.AppState
where

import Control.Lens
import Data.Map.Strict      (Map, empty)
import Kafka.Consumer.Types
import Kafka.Types

data AppState = AppState
  { _partitionOffsetMap :: Map (TopicName, PartitionId) PartitionOffset
  , _filesCount         :: Int
  }

appStateEmpty :: AppState
appStateEmpty = AppState empty 0

makeLenses ''AppState
