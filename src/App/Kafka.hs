module App.Kafka
where

import App.Options
import Control.Concurrent           (MVar, putMVar, takeMVar)
import Control.Lens                 hiding (cons)
import Control.Monad                (void)
import Control.Monad.IO.Class       (MonadIO, liftIO)
import Control.Monad.Trans.Resource
import Data.Conduit                 (Sink, Source, awaitForever, yieldM)
import Data.Monoid                  ((<>))
import Kafka.Conduit


mkConsumer :: MonadResource m => ServiceOptions -> m KafkaConsumer
mkConsumer opts =
  let props = consumerBrokersList [opts ^. optKafkaBroker]
              <> groupId (opts ^. optKafkaGroupId)
              <> noAutoCommit
              <> consumerSuppressDisconnectLogs
              <> consumerQueuedMaxMessagesKBytes (opts ^. optKafkaQueuedMaxMessagesKBytes)
      sub = topics [opts ^. optInputTopic] <> offsetReset Earliest
      cons = newConsumer props sub >>= either throwM return
   in snd <$> allocate cons (void . closeConsumer)

mkProducer :: MonadResource m => ServiceOptions -> m KafkaProducer
mkProducer opts =
  let props = producerBrokersList [opts ^. optKafkaBroker]
              <> producerSuppressDisconnectLogs
      prod = newProducer props >>= either throwM return
   in snd <$> allocate prod closeProducer

mvarRecordSink :: MonadIO m => MVar a -> Sink a m ()
mvarRecordSink v = awaitForever (liftIO . putMVar v)

mvarSource :: MonadIO m => MVar a -> Source m a
mvarSource v = yieldM (liftIO $ takeMVar v) >> mvarSource v
