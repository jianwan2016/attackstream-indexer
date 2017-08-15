{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Main where

import App
import App.Index
import App.Kafka
import App.Submissions
import Arbor.Logger
import Control.Concurrent                   hiding (yield)
import Control.Concurrent.BoundedChan
import Control.Lens
import Control.Monad                        (void)
import Control.Monad.IO.Class               (MonadIO, liftIO)
import Control.Monad.State.Class
import Control.Monad.State.Strict           (MonadState (..))
import Control.Monad.Trans.AWS
import Data.Conduit
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro                           (schemaRegistry)
import Kafka.Conduit.Sink
import System.Environment
import System.IO                            (stdout)

import qualified Data.Conduit.List as L
import qualified Data.Map          as M
import qualified Data.Text         as T
import qualified Service           as Srv

main :: IO ()
main = do
  opt <- parseOptions

  case opt of
    CmdService opt' -> serviceMain  opt'
    CmdIndex   opt' -> indexMain    opt'

serviceMain :: ServiceOptions -> IO ()
serviceMain opt = do
  submissionsReady <- newBoundedChan (opt ^. optPrefetchSize)
  env <- mkEnv opt
  progName <- T.pack <$> getProgName

  void . runApplication progName env opt $ do
    logInfo "Instantiating Schema Registry"
    sr <- schemaRegistry (opt ^. optKafkaSchemaRegistryAddress)

    logInfo "Creating Kafka Consumer"
    consumer <- mkConsumer opt

    logInfo "Spawning prefetcher"
    _ <- forkIOThrowInParent . runSubmissionsService env (opt ^. optLogLevel) .
      void . runConduit $
        submissions consumer (opt ^. optKafkaPollTimeoutMs) sr
        .| boundedChanRecordSink submissionsReady

    logInfo "Processing submissions"
    runConduit $
      boundedChanSource submissionsReady
        .| tap (L.catMaybes .| Srv.handleStream (opt ^. optXmlIndexBucket))
        .| effect updateOffsetMap
        .| everyNSeconds (opt ^. optKafkaConsumerCommitPeriodSec)
        .| effect (\_ -> get >>= logInfo . show . _filesCount)
        .| commitStoredOffsetsSink consumer

    logError "Premature exit, must not happen."

mkEnv :: ServiceOptions -> IO Env
mkEnv opt = do
  lgr <- newLogger (awsLogLevel opt) stdout
  newEnv Discover <&> (envLogger .~ lgr) . set envRegion (opt ^. optRegion)

forkIOThrowInParent :: MonadIO m => IO a -> m ThreadId
forkIOThrowInParent f = liftIO $ do
  parent <- myThreadId
  forkFinally f $ either (throwTo parent) (const (pure ()))

updateOffsetMap :: MonadState AppState m => Maybe (ConsumerRecord k v) -> m ()
updateOffsetMap Nothing = pure ()
updateOffsetMap (Just cr) =
  let pid        = crPartition cr
      topic      = crTopic cr
      (Offset i) = crOffset cr
  in modify (partitionOffsetMap %~ M.insert (topic, pid) (PartitionOffset i))

commitStoredOffsetsSink :: (MonadIO m, MonadState AppState m) => KafkaConsumer -> Sink a m ()
commitStoredOffsetsSink c = awaitForever $ \_ -> do
  appState <- get
  let topicPartitions = appState ^. partitionOffsetMap & M.toList <&> (\((t, p), o) -> TopicPartition t p (offsetToPosition o))
  _ <- commitPartitionsOffsets OffsetCommit c topicPartitions
  put appStateEmpty
  where
    -- we really need another type for that, in a library
    offsetToPosition po = case po of
      PartitionOffset o -> PartitionOffset (o+1)
      offset            -> offset
