{-# LANGUAGE BangPatterns         #-}
{-# LANGUAGE ScopedTypeVariables  #-}

module App.Index where

import App
import Data.Conduit.Combinators
import Control.Lens
import Data.Conduit
import Data.Monoid                                        ((<>))
import Data.Serialize
import Data.Time.Clock.POSIX
import Data.Word
import Foreign
import HaskellWorks.Data.BalancedParens.Simple
import HaskellWorks.Data.Bits.BitShown
import HaskellWorks.Data.FromByteString
import HaskellWorks.Data.Xml.Conduit
import HaskellWorks.Data.Xml.Conduit.Blank
import HaskellWorks.Data.Xml.Index
import HaskellWorks.Data.Xml.Succinct.Cursor.BlankedXml
import HaskellWorks.Data.Xml.Succinct.Cursor.InterestBits
import Prelude                                            as P
import System.IO.MMap

import qualified Data.ByteString                                      as BS
import qualified Data.ByteString.Internal                             as BSI
import qualified Data.ByteString.Lazy                                 as BSL
import qualified Data.Vector.Storable                                 as DVS
import qualified HaskellWorks.Data.Xml.Succinct.Cursor.BalancedParens as CBP

{-# ANN module ("HLint: ignore Reduce duplication"  :: String) #-}

indexMain :: IndexOptions -> IO ()
indexMain opt = case opt ^. optIndexMethod of
  IndexInMemory -> indexInMemory  opt
  IndexBlank    -> indexBlank     opt
  IndexBp       -> indexBp        opt
  IndexIdx      -> indexIdx       opt
  IndexCat      -> indexCat       opt

indexInMemory :: IndexOptions -> IO ()
indexInMemory opt = do
  let filename = opt ^. optFilename

  putStrLn $ "Indexing in memory: " <> show filename

  !timeA  <- getPOSIXTime
  !textBs <- BS.readFile filename

  let !blankedXml = fromByteString textBs :: BlankedXml
  !timeB <- getPOSIXTime
  putStrLn $ "Produced blanked XML in " <> show (timeB - timeA)

  let !_ = getXmlInterestBits       (fromBlankedXml blankedXml) :: BitShown (DVS.Vector Word64)
  !timeC <- getPOSIXTime
  putStrLn $ "Produced interest bits in " <> show (timeC - timeB)

  let !_ = CBP.getXmlBalancedParens (fromBlankedXml blankedXml) :: SimpleBalancedParens (DVS.Vector Word64)
  !timeD <- getPOSIXTime
  putStrLn $ "Produced balanced parens in " <> show (timeD - timeC)

  return ()

indexBp :: IndexOptions -> IO ()
indexBp opt = do
  let filename = opt ^. optFilename

  putStrLn $ "Indexing via file: " <> show filename

  !timeA  <- getPOSIXTime

  runConduitRes
    $   sourceFileBS filename
    .|  blankXml
    .|  blankedXmlToBalancedParens2
    .|  compressWordAsBit
    .|  sinkFileBS (filename <> ".bp")

  !timeB <- getPOSIXTime
  putStrLn $ "Produced blanked XML in " <> show (timeB - timeA)

loadVector :: FilePath -> IO (DVS.Vector Word64)
loadVector filepath = do
  (fptr :: ForeignPtr Word8, offset, size) <- mmapFileForeignPtr filepath ReadOnly Nothing
  let !bs = fromByteString (BSI.fromForeignPtr (castForeignPtr fptr) offset size)
  return bs

indexIdx :: IndexOptions -> IO ()
indexIdx opt = do
  let filename = opt ^. optFilename

  putStrLn $ "Indexing via file: " <> show filename

  !timeA  <- getPOSIXTime

  runConduitRes
    $   sourceFileBS filename
    .|  blankXml
    .|  sinkFileBS (filename <> ".blank")

  runConduitRes
    $   sourceFileBS (filename <> ".blank")
    .|  blankedXmlToInterestBits
    .|  sinkFileBS (filename <> ".ib")

  runConduitRes
    $   sourceFileBS (filename <> ".blank")
    .|  blankedXmlToBalancedParens2
    .|  compressWordAsBit
    .|  sinkFileBS (filename <> ".bp")

  ibData <- loadVector (filename <> ".ib")
  bpData <- loadVector (filename <> ".bp")

  let idx = Index "1.0" (BitShown ibData) (BitShown bpData)

  BSL.writeFile (filename <> ".idx") (encodeLazy idx)

  !timeB <- getPOSIXTime
  putStrLn $ "Produced blanked XML in " <> show (timeB - timeA)

indexBlank :: IndexOptions -> IO ()
indexBlank opt = do
  let filename = opt ^. optFilename

  putStrLn $ "Indexing via file: " <> show filename

  !timeA  <- getPOSIXTime

  runConduitRes
    $   sourceFileBS filename
    .|  blankXml
    .|  sinkFileBS (filename <> ".blank")

  !timeB <- getPOSIXTime
  putStrLn $ "Produced blanked XML in " <> show (timeB - timeA)

cat :: Monad m => Conduit BS.ByteString m BS.ByteString
cat = do
  mbs <- await
  case mbs of
    Just bs -> do
      yield (fst (BS.unfoldrN (BS.length bs) BS.uncons bs))
      cat
    Nothing -> return ()

indexCat :: IndexOptions -> IO ()
indexCat opt = do
  let filename = opt ^. optFilename

  putStrLn $ "Indexing via file: " <> show filename

  !timeA  <- getPOSIXTime

  runConduitRes
    $   sourceFileBS filename
    .|  cat
    .|  sinkFileBS (filename <> ".copy")

  !timeB <- getPOSIXTime
  putStrLn $ "Produced blanked XML in " <> show (timeB - timeA)
