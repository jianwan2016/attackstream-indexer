module App.AppError
where

import Control.Monad.Catch
import Data.Bifunctor      (first)
import Kafka.Avro
import Kafka.Types

data AppError = KafkaErr KafkaError
              | DecodeErr DecodeError
              | AppErr String
              deriving (Show, Eq)
instance Exception AppError

boxErrors :: Either KafkaError a -> Either AppError a
boxErrors = first KafkaErr

throwAs :: MonadThrow m => (e -> AppError) -> Either e a -> m a
throwAs f = either (throwM . f) pure
