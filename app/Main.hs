{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Main where

import App
import App.Index
import App.Kafka
import App.Submissions
import Arbor.Logger
import Control.Concurrent                   hiding (yield)
import Control.Lens
import Control.Monad                        (void)
import Control.Monad.IO.Class               (MonadIO, liftIO)
import Control.Monad.State.Strict           (MonadState (..))
import Control.Monad.Trans.AWS
import Data.Conduit
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro                           (schemaRegistry)
import System.Environment
import System.IO                            (stdout)

import qualified Data.Conduit.List as L
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
  submissionReady <- newEmptyMVar
  env <- mkEnv opt
  progName <- T.pack <$> getProgName
  emptyVar <- newEmptyMVar

  void . runApplication progName env opt $ do
    logInfo "Instantiating Schema Registry"
    sr <- schemaRegistry (opt ^. optKafkaSchemaRegistryAddress)

    logInfo "Creating Kafka Consumer"
    consumer <- mkConsumer opt

    logInfo "Spawning prefetcher"
    _ <- forkIOThrowInParent . runSubmissionsService env (opt ^. optLogLevel) .
      void . runConduit $
        submissions consumer (opt ^. optKafkaPollTimeoutMs) sr (opt ^. optXmlIndexBucket)
        .| mvarRecordSink submissionReady

    logInfo "Processing submissions"
    runConduit $
      mvarSource submissionReady
        .| tap (L.catMaybes .| Srv.handleStream (opt ^. optXmlIndexBucket))
        .| effect (\_ -> get >>= logInfo . show . _filesCount)
        .| mvarSink emptyVar

    logError "Premature exit, must not happen."

mkEnv :: ServiceOptions -> IO Env
mkEnv opt = do
  lgr <- newLogger (awsLogLevel opt) stdout
  newEnv Discover <&> (envLogger .~ lgr) . set envRegion (opt ^. optRegion)

forkIOThrowInParent :: MonadIO m => IO a -> m ThreadId
forkIOThrowInParent f = liftIO $ do
  parent <- myThreadId
  forkFinally f $ either (throwTo parent) (const (pure ()))
