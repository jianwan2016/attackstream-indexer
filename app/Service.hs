{-# LANGUAGE ScopedTypeVariables #-}
module Service
where

import Arbor.Logger
import Control.Lens
import Control.Monad.Catch                  (throwM)
import Data.Conduit
import Data.Semigroup                       ((<>))
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Consumer.Types
import Network.AWS                          (MonadAWS)
import Network.StatsD.Datadog               hiding (encodeValue)
import Network.StatsD.Monad

import App
import App.FileChange
import App.XmlIndexFile

import qualified App.Submissions   as S
import qualified Data.Conduit.List as L
import qualified Data.Text         as T
import           Network.AWS.S3

extractFound :: MonadLogger m => Conduit S.SubmissionResult m S.Submission
extractFound = awaitForever $ \x -> case x of
  S.SubmissionOk s -> yield s
  S.SubmissionNotFound msg -> logWarn ("Submission file not found: " <> show msg)

handleStream :: (MonadApp m, MonadAWS m)
             => BucketName
             -> Sink (ConsumerRecord k S.SubmissionResult) m ()
handleStream bucketName =
  L.map crValue
  .| extractFound
  .| effect (\x -> logInfo $ "[Handle] " <> show (S.submissionFile x))
  .| L.filter (not . isIndexFileName . T.unpack . fileChangeMessageObjectKey . S.submissionFile)
  .| L.mapM indexXmlFileEither
  .| L.mapM (uploadResultToBucket bucketName)
  .| L.mapM handleErrors
  .| L.mapM submitProcessedMetric
  .| L.mapM_ (const (filesCount += 1))

uploadResultToBucket :: (MonadApp m, MonadAWS m)
             => BucketName
             -> Either AppError XmlIndexFile
             -> m (Either AppError XmlIndexFile)
uploadResultToBucket _ (Left e) = return (Left e)
uploadResultToBucket bucketName (Right xi) = do
  let err = Left $ AwsErr "Cannot upload to bucket!"
  res <- uploadXmlIndexFile bucketName xi
  return $ if res then Right xi else err

submitProcessedMetric :: MonadApp m => () -> m ()
submitProcessedMetric _ = do
  sendMetric (addCounter (MetricName "submission.processed.count") (const 1) ())
  return ()

handleErrors :: MonadApp m
             => Either AppError XmlIndexFile
             -> m ()
handleErrors (Right _) = return ()
handleErrors (Left e) = do
  case e of
    CorruptedFile _ -> sendMetric (addCounter (MetricName "submission.corrupted.count") (const 1) ())
    _               -> throwM e
  return ()
