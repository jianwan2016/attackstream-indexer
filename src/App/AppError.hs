module App.AppError
where

import Control.Monad.Catch
import Kafka.Avro

data AppError = AwsErr String
              | DecodeErr DecodeError
              | CorruptedFile FilePath
              | AppErr String
              deriving (Show, Eq)
instance Exception AppError

throwAs :: MonadThrow m => (e -> AppError) -> Either e a -> m a
throwAs f = either (throwM . f) pure
