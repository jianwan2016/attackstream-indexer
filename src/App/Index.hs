{-# LANGUAGE BangPatterns #-}

module App.Index where

import App
import Data.Conduit.Combinators
import Control.Lens
import Data.Conduit
import Data.Monoid                                        ((<>))
import Data.Time.Clock.POSIX
import Data.Word
import HaskellWorks.Data.BalancedParens.Simple
import HaskellWorks.Data.Bits.BitShown
import HaskellWorks.Data.FromByteString
import HaskellWorks.Data.Xml.Conduit
import HaskellWorks.Data.Xml.Conduit.Blank
import HaskellWorks.Data.Xml.Succinct.Cursor.BlankedXml
import HaskellWorks.Data.Xml.Succinct.Cursor.InterestBits
import Prelude                                            as P

import qualified Data.ByteString                                      as BS
import qualified Data.Vector.Storable                                 as DVS
import qualified HaskellWorks.Data.Xml.Succinct.Cursor.BalancedParens as CBP

indexMain :: IndexOptions -> IO ()
indexMain opt = case opt ^. optIndexMethod of
  IndexInMemory -> indexInMemory  opt
  IndexBlank    -> indexBlank     opt
  IndexBp       -> indexBp        opt

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
