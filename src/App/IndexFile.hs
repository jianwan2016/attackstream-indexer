{-# LANGUAGE RecordWildCards #-}
module App.IndexFile where

import Data.ByteString.Conversion
import Data.ByteString.Char8
import Data.Char (chr)
import Data.Word
import HaskellWorks.Data.Xml
import HaskellWorks.Data.Xml.Succinct.Cursor.Internal
import HaskellWorks.Data.RankSelect.Poppy512S
import HaskellWorks.Data.BalancedParens.RangeMinMax
import qualified Data.Vector.Storable as DVS
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy.Internal as BLI
import qualified Data.ByteString as BS
import Text.XML.Light

--TODO duplicates code in unifier - move to common place
type Cursor = XmlCursor BS.ByteString Poppy512S (RangeMinMax Poppy512S)

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
word64ToStrictBS w = BLI.foldlChunks append BS.empty (toByteString w)

vectorToStrictBS :: DVS.Vector Word64 -> BS.ByteString
vectorToStrictBS = DVS.foldl' f BS.empty
  where f bs w = bs `append` word64ToStrictBS w

indexVectorToString :: DVS.Vector Word64 -> String
indexVectorToString v = Prelude.map (chr . fromIntegral) wordList
  where
    bs = vectorToStrictBS v
    encodedBS = Base64.encode bs
    wordList = BS.unpack encodedBS :: [Word8]

cursorToIndexByteString :: Cursor -> String
cursorToIndexByteString (XmlCursor _ (Poppy512S interestsVector _ _)
    (RangeMinMax (Poppy512S balancedParensVector _ _) _ _ _ _ _ _ _ _ _ ) _ ) = ppcTopElement xmlSettings indexElem
  where
    interests' = indexVectorToString interestsVector
    balancedParens' = indexVectorToString balancedParensVector
    xmlSettings = useShortEmptyTags (const False) defaultConfigPP
    indexElem = unode "index" $ XmlIndex xmlIndexVersion interests' balancedParens'
