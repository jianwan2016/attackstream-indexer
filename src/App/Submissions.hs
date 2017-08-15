{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections       #-}
module App.Submissions
where

import Arbor.Logger
import Control.Concurrent.Async
import Control.Concurrent.BoundedChan
import Control.Lens
import Control.Monad (void)
import Control.Monad.IO.Class
import Control.Monad.Trans.Resource
import Data.Bifunctor
import Data.ByteString                      (ByteString)
import Data.ByteString.Lazy                 (fromStrict)
import Data.Conduit
import Data.Semigroup                       ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro                           (SchemaRegistry, decodeWithSchema)
import Kafka.Conduit.Source
import Network.AWS                          (MonadAWS, HasEnv, runAWS)

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


data SubmissionResult
  = SubmissionOk Submission
  | SubmissionNotFound FileChangeMessage
  deriving (Eq, Show)

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
              -> BoundedChan (Maybe (ConsumerRecord () (Async SubmissionResult)))
              -> IO ()
runPrefetcher env opt sr consumer submissionsReady = runSubmissionsService env (opt ^. optLogLevel) $
    void . runConduit $
      kafkaSourceNoClose consumer (opt ^. optKafkaPollTimeoutMs)
      .| throwLeftSatisfy isFatal
      .| skipNonFatalExcept [isPollTimeout]
      .| L.map (either (const Nothing) Just)
      .| inJust (decodeRecords env sr)
      .| boundedChanRecordSink submissionsReady

decodeRecords :: (MonadLogger m, MonadResource m, MonadAWS m, HasEnv e)
              => e
              -> SchemaRegistry
              -> Conduit (ConsumerRecord k (Maybe ByteString)) m (ConsumerRecord () (Async SubmissionResult))
decodeRecords env sr =
  L.map (first (const ()))
  .| L.map sequence
  .| L.catMaybes
  .| L.mapM (traverse $ decodeMessage sr)
  .| L.filter (\x -> fileChangeMessageObjectSize (crValue x) > 0)
  .| effect (\x -> logDebug $ "[Prefetch] " <> (T.unpack . fileChangeMessageObjectKey . crValue) x)
  .| L.mapM (\r -> do
              let v = crValue r
              res <- liftIO $ async (runResourceT (runAWS env (loadFileStream v)))
              let asyncMaybeSubmission = const res <$> r
              return asyncMaybeSubmission
            )

decodeMessage :: (MonadIO m, MonadThrow m) => SchemaRegistry -> ByteString -> m FileChangeMessage
decodeMessage sr bs = decodeWithSchema sr (fromStrict bs) >>= throwAs DecodeErr

loadFileStream :: (MonadResource m, MonadAWS m) => FileChangeMessage -> m SubmissionResult
loadFileStream msg = do
  let bucket = BucketName $ fileChangeMessageBucketName msg
      objKey = ObjectKey  $ fileChangeMessageObjectKey msg
  fileContent <- downloadLBS' bucket objKey
  case fileContent of
    Nothing -> pure (SubmissionNotFound msg)
    Just lbs -> return . SubmissionOk $ Submission msg lbs
