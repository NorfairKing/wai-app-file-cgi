{-# LANGUAGE OverloadedStrings #-}

module Network.Wai.Application.Classic.File (
    fileApp
  ) where

import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as BL ()
import Network.Wai
import Network.Wai.Application.Classic.Field
import Network.Wai.Application.Classic.FileInfo
import Network.Wai.Application.Classic.MaybeIter
import Network.Wai.Application.Classic.Types

----------------------------------------------------------------

{-|
  Handle GET and HEAD for a static file.

If 'pathInfo' ends with \'/\', 'indexFile' is automatically
added. In this case, "Acceptable-Language:" is also handled.  Suppose
'indexFile' is "index.html" and if the value is "ja,en", then
\"index.html.ja\", \"index.html.en\", and \"index.html\" are tried to be
opened in order.

If 'pathInfo' does not end with \'/\' and a corresponding index file
exist, redirection is specified in HTTP response.

Directory contents are NOT automatically listed. To list directory
contents, an index file must be created beforehand.

The following HTTP headers are handled: Acceptable-Language:,
If-Modified-Since:. (Range:, If-Range:, If-Unmodified-Since:)
-}

fileApp :: AppSpec -> FileRoute -> Application
fileApp spec filei req = do
    RspSpec st hdr body <- case method of
        "GET"  -> processGET  req file ishtml rfile
        "HEAD" -> processHEAD req file ishtml rfile
        _      -> return $ notAllowed
    liftIO $ logger spec req st
    let hdr' = addHeader hdr
    case body of
        NoBody           -> return $ responseLBS st hdr' ""
        BodyLBS bd       -> return $ responseLBS st hdr' bd
        BodyFile afile _ -> return $ ResponseFile st hdr' afile -- FIXME size
  where
    method = requestMethod req
    path = pathinfoToFilePath req filei
    file = addIndex spec path
    ishtml = isHTML spec file
    rfile = redirectPath spec path
    addHeader hdr = ("Server", softwareName spec) : hdr

----------------------------------------------------------------

processGET :: Request -> FilePath -> Bool -> (Maybe FilePath) -> Rsp
processGET req file ishtml rfile = runAny [
    tryGet req file ishtml langs
  , tryRedirect req rfile langs
  , just notFound
  ]
  where
    langs = map ('.':) (languages req) ++ ["",".en"]

tryGet :: Request -> FilePath -> Bool -> [String] -> MRsp
tryGet req file True langs = runAnyMaybe $ map (tryGetFile req file) langs
tryGet req file _    _     = tryGetFile req file ""

tryGetFile :: Request -> FilePath -> String -> MRsp
tryGetFile req file lang = do
    let file' = if null lang then file else file ++ lang
    (liftIO $ fileInfo file') |>| \(size, mtime) -> do
      let hdr = newHeader file mtime
          mst = ifmodified req size mtime
            ||| ifunmodified req size mtime
            ||| ifrange req size mtime
            ||| unconditional req size mtime
      case mst of
        Just st
          | st == statusOK -> just $ RspSpec statusOK hdr (BodyFile file' size)
          -- FIXME skip len
          | st == statusPartialContent -> undefined
          | otherwise      -> just $ RspSpec st hdr NoBody
        _                  -> nothing -- never reached

----------------------------------------------------------------

processHEAD :: Request -> FilePath -> Bool -> (Maybe FilePath) -> Rsp
processHEAD req file ishtml rfile = runAny [
    tryHead req file ishtml langs
  , tryRedirect req rfile langs
  , just notFound
  ]
  where
    langs = map ('.':) (languages req) ++ ["",".en"]

tryHead :: Request -> FilePath -> Bool -> [String] -> MRsp
tryHead req file True langs = runAnyMaybe $ map (tryHeadFile req file) langs
tryHead req file _    _     = tryHeadFile req file ""

tryHeadFile :: Request -> FilePath -> String -> MRsp
tryHeadFile req file lang = do
    let file' = if null lang then file else file ++ lang
    (liftIO $ fileInfo file') |>| \(size, mtime) -> do
      let hdr = newHeader file mtime
          mst = ifmodified req size mtime
            ||| Just statusOK
      case mst of
        Just st -> just $ RspSpec st hdr NoBody
        _       -> nothing -- never reached

----------------------------------------------------------------

tryRedirect  :: Request -> (Maybe FilePath) -> [String] -> MRsp
tryRedirect _   Nothing     _     = nothing
tryRedirect req (Just file) langs =
    runAnyMaybe $ map (tryRedirectFile req file) langs

tryRedirectFile :: Request -> FilePath -> String -> MRsp
tryRedirectFile req file lang = do
    let file' = file ++ lang
    minfo <- liftIO $ fileInfo file'
    case minfo of
      Nothing -> nothing
      Just _  -> just $ RspSpec statusMovedPermanently hdr NoBody
  where
    hdr = [("Location", redirectURL)]
    (+++) = BS.append
    redirectURL = "http://"
              +++ serverName req
              +++ ":"
              +++ (BS.pack . show . serverPort) req
              +++ pathInfo req
              +++ "/"

----------------------------------------------------------------

notFound :: RspSpec
notFound = RspSpec statusNotFound textPlain (BodyLBS "Not Found")

notAllowed :: RspSpec
notAllowed = RspSpec statusNotAllowed textPlain (BodyLBS "Method Not Allowed")