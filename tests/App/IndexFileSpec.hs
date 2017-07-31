{-# LANGUAGE ExplicitForAll            #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE InstanceSigs              #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE ScopedTypeVariables       #-}

{-# OPTIONS_GHC -fno-warn-missing-signatures #-}

module App.IndexFileSpec(spec) where

import           App.IndexFile

import           Test.Hspec
import qualified Data.ByteString.Char8 as C8

{-# ANN module ("HLint: ignore Redundant do"        :: String) #-}
{-# ANN module ("HLint: ignore Reduce duplication"  :: String) #-}

spec :: Spec
spec = describe "HaskellWorks.Data.Xml.Succinct.CursorSpec" $ do
  describe "Cursor for Element" $ do
    it "depth at top" $ do
      let cursor = mkCursor $ C8.pack "<widget debug='on'/>" :: Cursor
      let indexXml = "<?xml version='1.0' ?>\n<index><version>1.0</version><interests>MTY3Njk=</interests><balancedParens>MjM=</balancedParens></index>\n"
      cursorToIndexString cursor `shouldBe` indexXml
