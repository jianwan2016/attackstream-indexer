{-# LANGUAGE TemplateHaskell #-}
module App.FileChange
where

import Data.Avro.Deriving

deriveAvro "contract/fileChange.avsc"
