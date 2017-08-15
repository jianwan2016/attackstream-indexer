{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}
module App.Submissions
where

import Arbor.Logger
import Control.Concurrent.BoundedChan
import Control.Lens
import Control.Monad (void)
import Control.Monad.IO.Class
import Control.Monad.Trans.Resource
import Data.ByteString                      (ByteString)
import Data.ByteString.Lazy                 (fromStrict)
import Data.Conduit
import Data.Semigroup                       ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro                           (SchemaRegistry, decodeWithSchema)
import Kafka.Conduit.Source
import Network.AWS                          (MonadAWS, HasEnv)

import App
import App.AWS.S3
import App.FileChange
import App.Kafka

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

runPrefetcher :: HasEnv e
              => e
              -> ServiceOptions
              -> SchemaRegistry
              -> KafkaConsumer
              -> BoundedChan (Maybe (ConsumerRecord (Maybe Data.ByteString.ByteString) Submission))
              -> IO ()
runPrefetcher env opt sr consumer submissionsReady = runSubmissionsService env (opt ^. optLogLevel) $
    void . runConduit $
      submissions consumer (opt ^. optKafkaPollTimeoutMs) sr
      .| boundedChanRecordSink submissionsReady

submissions :: (MonadAWS m, MonadResource m, MonadLogger m)
            => KafkaConsumer
            -> Timeout
            -> SchemaRegistry
            -> Source m (Maybe (ConsumerRecord (Maybe ByteString) Submission))
submissions consumer timeout sr =
    kafkaSourceNoClose consumer timeout
    .| throwLeftSatisfy isFatal
    .| skipNonFatalExcept [isPollTimeout]
    .| L.map (either (const Nothing) Just)
    .| inJust (decodeRecords sr)

decodeRecords :: (MonadLogger m, MonadResource m, MonadAWS m)
              => SchemaRegistry
              -> Conduit (ConsumerRecord k (Maybe ByteString)) m (ConsumerRecord k Submission)
decodeRecords sr =
  L.map sequence
  .| L.catMaybes
  .| L.mapM (traverse $ decodeMessage sr)
  .| L.filter (\x -> fileChangeMessageObjectSize (crValue x) > 0)
  .| effect (\x -> logDebug $ "[Prefetch] " <> (T.unpack . fileChangeMessageObjectKey . crValue) x)
  .| L.mapM (traverse loadFileStream)
  .| L.map sequence
  .| L.catMaybes

decodeMessage :: (MonadIO m, MonadThrow m) => SchemaRegistry -> ByteString -> m FileChangeMessage
decodeMessage sr bs = decodeWithSchema sr (fromStrict bs) >>= throwAs DecodeErr

loadFileStream :: (MonadLogger m, MonadResource m, MonadAWS m) => FileChangeMessage -> m (Maybe Submission)
loadFileStream msg = do
  let bucket = BucketName $ fileChangeMessageBucketName msg
      objKey = ObjectKey  $ fileChangeMessageObjectKey msg
  fileContent <- downloadLBS' bucket objKey
  case fileContent of
    Nothing -> logWarn ("Submission file not found: " <> show msg) >> pure Nothing
    Just lbs -> return . Just $ Submission msg lbs
