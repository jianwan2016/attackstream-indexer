module App.IndexFileSpec(spec) where

import           App.IndexFile

import           Test.Hspec
import qualified Data.ByteString as BS
import qualified Data.ByteString.Internal as BSI (c2w)

{-# ANN module ("HLint: ignore Redundant do"        :: String) #-}
{-# ANN module ("HLint: ignore Reduce duplication"  :: String) #-}

spec :: Spec
spec = describe "HaskellWorks.Data.Xml.Succinct.CursorSpec" $ do
  describe "Cursor for Element" $ do
    it "index file content" $ do
      let bs = BS.pack $ map BSI.c2w "<widget debug='on'/>"
      let cursor = mkCursor bs
      let indexXml = "<?xml version='1.0' ?>\n<index><version>1.0</version><interests>MTY3Njk=</interests><balancedParens>MjM=</balancedParens></index>\n"
      cursorToIndexString cursor `shouldBe` indexXml
