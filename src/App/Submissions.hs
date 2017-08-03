{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}
module App.Submissions
where

import Arbor.Logger
import Control.Monad.IO.Class
import Control.Monad.Trans.Resource
import Data.ByteString                      (ByteString)
import Data.ByteString.Lazy                 (fromStrict)
import Data.Conduit
import Data.Semigroup                       ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro                           (SchemaRegistry, decodeWithSchema)
import Kafka.Conduit.Source
import Network.AWS                          (MonadAWS)

import App
import App.AWS.S3
import App.FileChange

import qualified Data.ByteString.Lazy as LBS
import qualified Data.Conduit.List    as L
import qualified Data.Text            as T

data Submission = Submission
  { submissionFile    :: FileChangeMessage
  , submissionContent :: LBS.ByteString
  } deriving (Eq, Show)

submissionFilePath :: FileChangeMessage -> FilePath
submissionFilePath fcm =
  let bucket = BucketName . fileChangeMessageBucketName $ fcm
      key = ObjectKey . fileChangeMessageObjectKey $ fcm
  in s3UriString bucket key

submissions :: (MonadAWS m, MonadResource m, MonadLogger m)
            => KafkaConsumer
            -> Timeout
            -> SchemaRegistry
            -> BucketName
            -> Source m (Maybe (ConsumerRecord (Maybe ByteString) Submission))
submissions consumer timeout sr ib =
    kafkaSourceNoClose consumer timeout
    .| throwLeftSatisfy isFatal
    .| skipNonFatalExcept [isPollTimeout]
    .| L.map (either (const Nothing) Just)
    .| inJust (decodeRecords sr ib)

decodeRecords :: (MonadLogger m, MonadResource m, MonadAWS m)
              => SchemaRegistry
              -> BucketName
              -> Conduit (ConsumerRecord k (Maybe ByteString)) m (ConsumerRecord k Submission)
decodeRecords sr ib =
  L.map sequence
  .| L.catMaybes
  .| L.mapM (traverse $ decodeMessage sr)
  .| L.filter (\x -> fileChangeMessageObjectSize (crValue x) > 0)
  .| effect (\x -> logDebug $ "[Prefetch] " <> (T.unpack . fileChangeMessageObjectKey . crValue) x)
  .| L.mapM (traverse (loadFileStream ib))

decodeMessage :: (MonadIO m, MonadThrow m) => SchemaRegistry -> ByteString -> m FileChangeMessage
decodeMessage sr bs = decodeWithSchema sr (fromStrict bs) >>= throwAs DecodeErr

loadFileStream :: (MonadResource m, MonadAWS m) => BucketName -> FileChangeMessage -> m Submission
loadFileStream ib msg =
  let objKey = ObjectKey $ fileChangeMessageObjectKey msg
  in Submission msg <$> downloadLBS ib objKey
