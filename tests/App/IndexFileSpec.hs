module App.IndexFileSpec(spec) where

import           App.XmlIndexFile

import           Test.Hspec
import qualified Data.ByteString as BS

import qualified Data.ByteString.Lazy     as BL
import qualified Data.ByteString.Conversion as C
import HaskellWorks.Data.Bits.BitShow
import HaskellWorks.Data.Xml
import HaskellWorks.Data.BalancedParens.Simple
import HaskellWorks.Data.Bits.BitShown
import HaskellWorks.Data.FromByteString
import HaskellWorks.Data.Xml.Index

{-# ANN module ("HLint: ignore Redundant do"        :: String) #-}
{-# ANN module ("HLint: ignore Reduce duplication"  :: String) #-}

interestsString :: BS.ByteString -> String
interestsString bs = bitShow ib
  where
    XmlCursor _ (BitShown ib) _ _ = fromByteString bs :: SimpleCursor

balancedParensString :: BS.ByteString -> String
balancedParensString bs = bitShow bp
  where
    XmlCursor _ _ (SimpleBalancedParens bp)  _ = fromByteString bs :: SimpleCursor

spec :: Spec
spec = describe "App.IndexFileSpec" $ do
  describe "Xml IndexFile" $ do
    it "file content" $ do
      let fpath = "fpath"
      let bs = BL.toStrict $ C.toByteString ("<t  a='av' />tv</t>" :: String)
      --                                      ( ( ()(  ) ))()
      --                                      10101010000001000000 - interests
      --                                      1110100010 - balancedParens
      let xi = xmlIndex fpath bs
      let index = xiIndex xi
      xiFilepath xi `shouldBe` fpath
      xiVersion  index `shouldBe` indexVersion
      bitShow (xiInterests      index) `shouldBe` interestsString bs
      bitShow (xiBalancedParens index) `shouldBe` balancedParensString bs
