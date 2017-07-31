{-# LANGUAGE BangPatterns        #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module App.XmlIndexFile where

import App.AppError
import App.AWS.S3
import App.FileChange
import App.Compression
import qualified App.Submissions          as S

import Arbor.Logger
import Control.Exception                         (SomeException)
import Control.Monad.Catch                       (MonadCatch, catch)
import Data.Maybe
import Data.Semigroup                            ((<>))
import Data.Serialize
import Data.String.Utils
import Data.Word
import HaskellWorks.Data.Xml
import HaskellWorks.Data.BalancedParens.Simple
import HaskellWorks.Data.Bits.BitShown
import HaskellWorks.Data.FromByteString
import HaskellWorks.Data.Xml.Index
import qualified Data.Vector.Storable as DVS
import qualified Data.ByteString as BS
import qualified Data.ByteString.Internal as BSI (c2w)
import qualified Data.ByteString.Lazy     as BL
import qualified Data.Text as T
import Network.AWS                               (MonadAWS)

type SimpleCursor = XmlCursor BS.ByteString (BitShown (DVS.Vector Word64)) (SimpleBalancedParens (DVS.Vector Word64))

indexFileSuffix :: String
indexFileSuffix = ".idx"

indexFileName :: String -> String
indexFileName fname = fname <> indexFileSuffix

isIndexFileName :: String -> Bool
isIndexFileName = endswith indexFileSuffix

data XmlIndexFile = XmlIndexFile
  { xiFilepath     :: String
  , xiIndex        :: Index
  }

indexXmlFileEither :: (MonadCatch m, MonadLogger m, MonadAWS m)
                    => S.Submission
                    -> m (Either AppError XmlIndexFile)
indexXmlFileEither sub = do
  !bs <- readStrictBS `catch` \(e :: SomeException) -> logError (show e <> ": " <> show (S.submissionFile sub)) >> pure BS.empty
  if BS.null (BS.dropWhile (== BSI.c2w ' ') bs) then return $ Left (CorruptedFile (S.submissionFilePath $ S.submissionFile sub))
  else do
    let path' = indexFileName . T.unpack . fileChangeMessageObjectKey $ S.submissionFile sub
    return . Right $ xmlIndex path' bs
  where
    readStrictBS = do
       let !str = (BL.toStrict . decompressIfCompressed) (S.submissionContent sub)
       return str

xmlIndex :: String -> BS.ByteString -> XmlIndexFile
xmlIndex path bs = XmlIndexFile path (Index indexVersion ib (BitShown bp))
  where
    XmlCursor _ ib (SimpleBalancedParens bp) _ = fromByteString bs :: SimpleCursor

uploadXmlIndexFile :: MonadAWS m => BucketName -> XmlIndexFile -> m Bool
uploadXmlIndexFile bucketName xi = do
    let bucketPath = ObjectKey . T.pack $ xiFilepath xi
    let indexData = encodeLazy (xiIndex xi)
    res <- App.AWS.S3.putByteString bucketName bucketPath indexData
    return $ isJust res
