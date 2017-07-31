module App.Compression where

import qualified Data.ByteString.Lazy as BS
import Codec.Compression.GZip
import Data.Bool
import Control.Applicative

--first two two bytes of each member are '\x1F' and '\x8B'
--http://www.gzip.org/zlib/rfc-gzip.html#header-trailer

gzipMagicBytes :: BS.ByteString
gzipMagicBytes =  BS.pack [ 0x1F,  0x8B]

isGzipCompressed :: BS.ByteString -> Bool
isGzipCompressed = (gzipMagicBytes ==) . BS.take 2

decompressIfCompressed :: BS.ByteString -> BS.ByteString
decompressIfCompressed =  liftA3 bool id decompress isGzipCompressed
