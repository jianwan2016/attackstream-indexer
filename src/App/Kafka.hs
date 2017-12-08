module App.Kafka where

import App.Options
import Control.Concurrent             (MVar, putMVar, takeMVar)
import Control.Concurrent.BoundedChan
import Control.Lens                   hiding (cons)
import Control.Monad                  (void)
import Control.Monad.IO.Class         (MonadIO, liftIO)
import Control.Monad.Trans.Resource
import Data.Conduit                   (Sink, Source, awaitForever, yieldM)
import Data.Monoid                    ((<>))
import Kafka.Conduit.Sink             as KSnk
import Kafka.Conduit.Source           as KSrc

mkConsumer :: MonadResource m => ServiceOptions -> m KafkaConsumer
mkConsumer opts =
  let props = KSrc.brokersList [opts ^. optKafkaBroker]
              <> groupId (opts ^. optKafkaGroupId)
              <> noAutoCommit
              <> KSrc.suppressDisconnectLogs
              <> queuedMaxMessagesKBytes (opts ^. optKafkaQueuedMaxMessagesKBytes)
      sub = topics [opts ^. optInputTopic] <> offsetReset Earliest
      cons = newConsumer props sub >>= either throwM return
   in snd <$> allocate cons (void . closeConsumer)

mkProducer :: MonadResource m => ServiceOptions -> m KafkaProducer
mkProducer opts =
  let props = KSnk.brokersList [opts ^. optKafkaBroker]
              <> KSnk.suppressDisconnectLogs
              <> KSnk.sendTimeout (Timeout 0) -- message sending timeout, 0 means "no timeout"
      prod = newProducer props >>= either throwM return
   in snd <$> allocate prod closeProducer

mvarRecordSink :: MonadIO m => MVar a -> Sink a m ()
mvarRecordSink v = awaitForever (liftIO . putMVar v)

mvarSource :: MonadIO m => MVar a -> Source m a
mvarSource v = yieldM (liftIO $ takeMVar v) >> mvarSource v

boundedChanSource :: MonadIO m => BoundedChan a -> Source m a
boundedChanSource chan = yieldM (liftIO $ readChan chan) >> boundedChanSource chan

boundedChanRecordSink :: MonadIO m => BoundedChan a -> Sink a m ()
boundedChanRecordSink chan = awaitForever (liftIO . writeChan chan)
