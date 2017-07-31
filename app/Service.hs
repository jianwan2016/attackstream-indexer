module Service
  ( handleStream
  )
where

import Arbor.Logger
import Control.Arrow                        (left)
import Control.Monad.IO.Class
import Data.ByteString                      (ByteString)
import Data.ByteString.Lazy                 (fromStrict)
import Data.Conduit
import Data.Semigroup                       ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro                           (SchemaRegistry, decodeWithSchema)
import Kafka.Conduit.Source
import Network.AWS.S3.Types                 (BucketName (..))

import qualified Data.Conduit.List as L

import           App
import qualified App.Submissions as S

handleStream :: MonadApp m
             => BucketName
             -> Sink (ConsumerRecord (Maybe ByteString) S.Submission) m ()
handleStream sr =
  L.map crValue
  .| effect (\x -> logInfo $ "[Handle] " <> show (S.submissionFile x))
  .| L.sinkNull
