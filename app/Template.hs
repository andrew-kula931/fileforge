module Template
  ( injectBody
  , loadLaTeXTemplate
  ) where

import qualified Data.ByteString.Lazy as BSL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TextEncoding
import System.Directory (doesPathExist)
import System.Exit (die)
import Text.Pandoc.Templates (Template, compileTemplate)

-- | Auto-inject '$body$' before '\end{document}' if it is not present in the template.
injectBody :: T.Text -> T.Text
injectBody tpl
  | T.isInfixOf (T.pack "$body$") tpl = tpl
  | otherwise =
      let (before, after) = T.breakOn (T.pack "\\end{document}") tpl
      in if T.null after
           then tpl <> T.pack "\n$body$\n"
           else before <> T.pack "\n$body$\n" <> after

-- | Load, preprocess, and compile a LaTeX template from disk.
loadLaTeXTemplate :: FilePath -> IO (Template T.Text)
loadLaTeXTemplate path = do
  exists <- doesPathExist path
  if not exists
    then die ("fileforge: template file does not exist: " ++ path)
    else do
      rawBytes <- BSL.readFile path
      content <- case TextEncoding.decodeUtf8' (BSL.toStrict rawBytes) of
        Left err -> die ("fileforge: invalid UTF-8 in " ++ path ++ ": " ++ show err)
        Right txt -> pure txt
      let prepared = injectBody content
      compiled <- compileTemplate path prepared
      case compiled of
        Left err -> die ("fileforge: template compilation failed: " ++ err)
        Right tpl -> pure tpl
