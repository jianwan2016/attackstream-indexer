module App.IndexFileSpec(spec) where

import App.IndexFile

import qualified Data.ByteString          as BS
import           Data.ByteString.Char8
import qualified Data.ByteString.Internal as BSI (c2w)
import qualified Data.ByteString.Lazy     as BL
import           Test.Hspec

{-# ANN module ("HLint: ignore Redundant do"        :: String) #-}
{-# ANN module ("HLint: ignore Reduce duplication"  :: String) #-}

spec :: Spec
spec = describe "HaskellWorks.Data.Xml.Succinct.CursorSpec" $ do
  describe "Cursor for Element" $ do
    it "index file content" $ do
      bs <- BL.readFile "data/submission-v7.xml"
      -- let bs = BS.pack $ map BSI.c2w "<widget debug='on'/>"
      let cursor = mkCursor $ BL.toStrict bs
      let indexXml = "<?xml version='1.0' ?>\n<index><version>1.0</version><interests>MTY3Njk=</interests><balancedParens>MjM=</balancedParens></index>\n"
      let str = cursorToIndexString cursor
      Prelude.writeFile "data/submission-v7.idx" str

      cursorToIndexString cursor `shouldBe` indexXml
