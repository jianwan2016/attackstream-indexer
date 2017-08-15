{-# LANGUAGE TemplateHaskell #-}

module App.Options where

import Control.Lens
import Control.Monad.Logger  (LogLevel (..))
import Data.Semigroup        ((<>))
import Data.Text             (Text)
import Network.AWS.Data.Text (FromText (..), fromText)
import Network.AWS.S3.Types  (BucketName (..), Region (..))
import Network.Socket        (HostName)
import Network.StatsD        (SampleRate (..))
import Options.Applicative
import Text.Read             (readEither)

import Kafka.Consumer.Types
import Kafka.Types

import qualified Data.Text   as T
import qualified Network.AWS as AWS

newtype StatsTag = StatsTag (Text, Text) deriving (Show, Eq)

data IndexMethod
  = IndexInMemory
  | IndexBlank
  | IndexBp
  | IndexCat
  | IndexIdx
  deriving (Eq, Show, Read)

data IndexOptions = IndexOptions
  { _optFilename    :: FilePath
  , _optIndexMethod :: IndexMethod
  } deriving (Eq, Show)

data Cmd
  = CmdService  ServiceOptions
  | CmdIndex    IndexOptions
  deriving (Eq, Show)

data ServiceOptions = ServiceOptions
  { _optLogLevel                     :: LogLevel
  , _optRegion                       :: Region
  , _optKafkaBroker                  :: BrokerAddress
  , _optKafkaSchemaRegistryAddress   :: String
  , _optKafkaPollTimeoutMs           :: Timeout
  , _optKafkaQueuedMaxMessagesKBytes :: Int
  , _optKafkaGroupId                 :: ConsumerGroupId
  , _optKafkaConsumerCommitPeriodSec :: Int
  , _optInputTopic                   :: TopicName
  , _optPrefetchSize                 :: Int
  , _optStatsdHost                   :: HostName
  , _optStatsdPort                   :: Int
  , _optStatsdTags                   :: [StatsTag]
  , _optSampleRate                   :: SampleRate
  , _optXmlIndexBucket               :: BucketName
  } deriving (Eq, Show)

makeLenses ''ServiceOptions

makeLenses ''IndexOptions

indexOptions :: Parser IndexOptions
indexOptions = IndexOptions
  <$> strOption
      (  long "filename"
      <> short 'f'
      <> metavar "FILENAME"
      <> help "File to index")
  <*> readOptionMsg "Valid values are IndexInMemory, IndexBlank, IndexBp"
      (  long "index-method"
      <> short 'm'
      <> metavar "INDEX_METHOD"
      <> help "Index method: IndexInMemory, IndexBlank, IndexBp")

serviceOptions :: Parser ServiceOptions
serviceOptions = ServiceOptions
  <$> readOptionMsg "Valid values are LevelDebug, LevelInfo, LevelWarn, LevelError"
        (  long "log-level"
        <> short 'l'
        <> metavar "LOG_LEVEL"
        <> showDefault <> value LevelInfo
        <> help "Log level.")
  <*> readOrFromTextOption
        (  long "region"
        <> short 'r'
        <> metavar "AWS_REGION"
        <> showDefault <> value Oregon
        <> help "The AWS region in which to operate"
        )
  <*> ( BrokerAddress <$> strOption
        (  long "kafka-broker"
        <> short 'b'
        <> metavar "ADDRESS:PORT"
        <> help "Kafka bootstrap broker"
        ))
  <*> strOption
        (  long "kafka-schema-registry"
        <> short 'r'
        <> metavar "HTTP_URL:PORT"
        <> help "Schema registry address")
  <*> (Timeout <$> readOption
        (  long "kafka-poll-timeout-ms"
        <> short 'u'
        <> metavar "KAFKA_POLL_TIMEOUT_MS"
        <> showDefault <> value 1000
        <> help "Kafka poll timeout (in milliseconds)"))
  <*> readOption
        (  long "kafka-queued-max-messages-kbytes"
        <> short 'q'
        <> metavar "KAFKA_QUEUED_MAX_MESSAGES_KBYTES"
        <> showDefault <> value 100000
        <> help "Kafka queued.max.messages.kbytes")
  <*> ( ConsumerGroupId <$> strOption
        (  long "kafka-group-id"
        <> short 'g'
        <> metavar "GROUP_ID"
        <> help "Kafka consumer group id"))
  <*> readOption
        (  long "kafka-consumer-commit-period-sec"
        <> short 'c'
        <> metavar "KAFKA_CONSUMER_COMMIT_PERIOD_SEC"
        <> showDefault <> value 60
        <> help "Kafka consumer offsets commit period (in seconds)"
        )
  <*> ( TopicName <$> strOption
        (  long "input-topic"
        <> short 'i'
        <> metavar "TOPIC"
        <> help "Input topic"))
  <*> readOption
        (  long "prefetch-size"
        <> short 'n'
        <> metavar "PREFETCH_SIZE"
        <> help "Maximum number of prefetches"
        )
  <*> strOption
        (  long "statsd-host"
        <> short 's'
        <> metavar "HOST_NAME"
        <> showDefault <> value "127.0.0.1"
        <> help "StatsD host name or IP address")
  <*> readOption
        (  long "statsd-port"
        <> short 'p'
        <> metavar "PORT"
        <> showDefault <> value 8125
        <> help "StatsD port"
        <> hidden)
  <*> ( string2Tags <$> strOption
        (  long "statsd-tags"
        <> short 't'
        <> metavar "TAGS"
        <> showDefault <> value []
        <> help "StatsD tags"))
  <*> ( SampleRate <$> readOption
        (  long "statsd-sample-rate"
        <> short 'a'
        <> metavar "SAMPLE_RATE"
        <> showDefault <> value 0.01
        <> help "StatsD sample rate"))
  <*> readOrFromTextOption
        (  long "xml-index-bucket"
        <> short 'x'
        <> metavar "XML_INDEX_BUCKET_NAME"
        <> help "XML index bucket name")

awsLogLevel :: ServiceOptions -> AWS.LogLevel
awsLogLevel o = case o ^. optLogLevel of
  LevelError -> AWS.Error
  LevelWarn  -> AWS.Error
  LevelInfo  -> AWS.Error
  LevelDebug -> AWS.Info
  _          -> AWS.Trace

readOption :: Read a => Mod OptionFields a -> Parser a
readOption = option $ eitherReader readEither

readOptionMsg :: Read a => String -> Mod OptionFields a -> Parser a
readOptionMsg msg = option $ eitherReader (either (Left . const msg) Right . readEither)

readOrFromTextOption :: (Read a, FromText a) => Mod OptionFields a -> Parser a
readOrFromTextOption =
  let fromStr s = readEither s <|> fromText (T.pack s)
  in option $ eitherReader fromStr

string2Tags :: String -> [StatsTag]
string2Tags s = StatsTag . splitTag <$> splitTags
  where
    splitTags = T.split (==',') (T.pack s)
    splitTag t = T.drop 1 <$> T.break (==':') t

serviceOptionsParser :: ParserInfo ServiceOptions
serviceOptionsParser = info (helper <*> serviceOptions)
  (  fullDesc
  <> progDesc "Service for indexing XML"
  <> header "Service for indexing XML"
  )

indexOptionsParser :: ParserInfo IndexOptions
indexOptionsParser = info (helper <*> indexOptions)
  (  fullDesc
  <> progDesc "Index a local XML file"
  <> header "Index an local XML file"
  )

optionsParser :: Parser Cmd
optionsParser = subparser
  (  command "service"  (CmdService <$> serviceOptionsParser)
  <> command "index"    (CmdIndex   <$> indexOptionsParser))

parseOptions :: IO Cmd
parseOptions = execParser $ info (helper <*> optionsParser)
  (  fullDesc
  <> progDesc "Service for indexing XML"
  <> header "Service for indexing XML"
  )
