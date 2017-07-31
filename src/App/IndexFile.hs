{-# LANGUAGE RecordWildCards #-}
module App.IndexFile where

import Data.ByteString.Char8
import Data.Char (chr)
import Data.Word
import HaskellWorks.Data.Xml
import HaskellWorks.Data.RankSelect.Poppy512S
import HaskellWorks.Data.BalancedParens.RangeMinMax
import qualified Data.Vector.Storable as DVS
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy.Internal as BLI
import qualified Data.ByteString as BS
import qualified Data.ByteString.Conversion as C
import Text.XML.Light

import HaskellWorks.Data.BalancedParens.Simple
import HaskellWorks.Data.Bits.BitShown
import HaskellWorks.Data.FromByteString

--TODO duplicates code in unifier - move to common place
type Cursor = XmlCursor BS.ByteString Poppy512S (RangeMinMax Poppy512S)

mkCursor :: BS.ByteString -> Cursor
mkCursor bs = XmlCursor text ibPoppy512 rangeMinMax 1
  where
    XmlCursor text (BitShown ib) (SimpleBalancedParens bp) _ = fromByteString bs
    bpPoppy512    = makePoppy512S bp
    rangeMinMax   = mkRangeMinMax bpPoppy512
    ibPoppy512    = makePoppy512S ib

--TODO hw-xml should have version too
--TODO compression? since we dont have it in index?

--TODO clean dependencies with `packunused`

xmlIndexVersion :: String
xmlIndexVersion = "1.0"

data XmlIndex = XmlIndex
  { xiVersion          :: String
  , xiInterests        :: String
  , xiBalancedParens   :: String
  }

instance Node XmlIndex where
  node qn XmlIndex {..} =
    node qn
      [ unode "version" xiVersion
      , unode "interests" xiInterests
      , unode "balancedParens" xiBalancedParens
      ]

word64ToStrictBS :: Word64 -> ByteString
word64ToStrictBS w = BLI.foldlChunks append BS.empty (C.toByteString w)

vectorToStrictBS :: DVS.Vector Word64 -> BS.ByteString
vectorToStrictBS = DVS.foldl' f BS.empty
  where f bs w = bs `append` word64ToStrictBS w

indexVectorToString :: DVS.Vector Word64 -> String
indexVectorToString v = Prelude.map (chr . fromIntegral) wordList
  where
    bs = vectorToStrictBS v
    encodedBS = Base64.encode bs
    wordList = BS.unpack encodedBS :: [Word8]

cursorToIndexString :: Cursor -> String
cursorToIndexString (XmlCursor _ (Poppy512S interestsVector _ _)
    (RangeMinMax (Poppy512S balancedParensVector _ _) _ _ _ _ _ _ _ _ _ ) _ ) = ppcTopElement xmlSettings indexElem
  where
    interests' = indexVectorToString interestsVector
    balancedParens' = indexVectorToString balancedParensVector
    xmlSettings = useShortEmptyTags (const False) defaultConfigPP
    indexElem = unode "index" $ XmlIndex xmlIndexVersion interests' balancedParens'
