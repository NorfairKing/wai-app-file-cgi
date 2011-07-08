{-# LANGUAGE OverloadedStrings #-}

module Network.Wai.Application.Classic.Utils (
    NumericAddress, showSockAddr
  , hasTrailingPathSeparator, pathSep
  , (+++), (</>)
  ) where

import Data.Bits
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.ByteString.Char8 ()
import Data.Word
import Network.Socket (SockAddr(..))
import Text.Printf

{-|
  A type for IP address in numeric string representation.
-}
type NumericAddress = String

-- SockAddr is host byte order thanks to peek32 in Network.Socket.Internal.
showIPv4 :: Word32 -> NumericAddress
showIPv4 w32 = show b4 ++ "." ++ show b3 ++ "." ++ show b2 ++ "." ++ show b1
  where
    t1 = w32
    t2 = shift t1 (-8)
    t3 = shift t2 (-8)
    t4 = shift t3 (-8)
    b1 = t1 .&. 0x000000ff
    b2 = t2 .&. 0x000000ff
    b3 = t3 .&. 0x000000ff
    b4 = t4 .&. 0x000000ff

showIPv6 :: (Word32,Word32,Word32,Word32) -> String
showIPv6 (w1,w2,w3,w4) =
    printf "%x:%x:%x:%x:%x:%x:%x:%x" s1 s2 s3 s4 s5 s6 s7 s8
  where
    (s1,s2) = foo w1
    (s3,s4) = foo w2
    (s5,s6) = foo w3
    (s7,s8) = foo w4
    foo w = (h1,h2)
      where
        h1 = w .&. 0x0000ffff
        h2 = (shift w (-16)) .&. 0x0000ffff
{-|
  Convert 'SockAddr' to 'NumericAddress'. If the address is
  an IPv4-embedded IPv6 address, the IPv4 is extracted.
-}
-- SockAddr is host byte order thanks to peek32 in Network.Socket.Internal.
showSockAddr :: SockAddr -> NumericAddress
showSockAddr (SockAddrInet _ addr4)                       = showIPv4 addr4
showSockAddr (SockAddrInet6 _ _ (0,0,0x0000ffff,addr4) _) = showIPv4 addr4
showSockAddr (SockAddrInet6 _ _ (0,0,0,1) _)              = "::1"
showSockAddr (SockAddrInet6 _ _ addr6 _)                  = showIPv6 addr6
showSockAddr _                                            = "unknownSocket"

pathSep :: Word8
pathSep = 47

hasTrailingPathSeparator :: ByteString -> Bool
hasTrailingPathSeparator "" = False
hasTrailingPathSeparator path
  | BS.last path == pathSep = True
  | otherwise               = False

infixr +++

(+++) :: ByteString -> ByteString -> ByteString
(+++) = BS.append

(</>) :: ByteString -> ByteString -> ByteString
s1 </> s2
  | hasTrailingPathSeparator s1 = s1 +++ s2
  | otherwise                   = s1 +++ (pathSep `BS.cons` s2)
