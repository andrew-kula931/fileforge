module Main where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString.Lazy as BSL
import Data.Char (toLower)
import Data.Maybe (isJust)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TextEncoding
import Options.Applicative
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , doesPathExist
  )
import System.Exit (die, ExitCode(..))
import System.FilePath
  ( (</>)
  , replaceExtension
  , takeDirectory
  , takeExtension
  )
import System.IO.Error (catchIOError)
import System.Process (readProcessWithExitCode)
import Template (loadLaTeXTemplate)
import Text.Pandoc
  ( def
  , Pandoc(..)
  , PandocIO
  , ReaderOptions(..)
  , WriterOptions(..)
  , Block(..)
  , Inline(..)
  , pandocExtensions
  , readDocx
  , readJSON
  , readLaTeX
  , readMarkdown
  , readXML
  , readXlsx
  , readCSV
  , writeDocx
  , writeJSON
  , writeLaTeX
  , writeMarkdown
  , writePlain
  , writeXML
  , runIO
  )
import Text.Pandoc.PDF (makePDF)
import Text.Pandoc.Templates (compileDefaultTemplate)

data Options = Options
  { inputFile     :: FilePath
  , outputFile    :: Maybe FilePath
  , formatted     :: Bool
  , extractAssets :: Bool
  , templateFile  :: Maybe FilePath
  } deriving (Show)

data OutputFormat
  = PlainText
  | Docx
  | Markdown
  | LaTeX
  | JSON
  | XML
  | PDF
  deriving (Show, Eq)

optionsParser :: Parser Options
optionsParser = Options
  <$> strOption
      ( long "input"
     <> short 'i'
     <> metavar "FILE"
     <> help "Input PDF, DOCX, Markdown, LaTeX, JSON, Xlsx, CSV, or XML file"
      )
  <*> optional
      (strOption
        ( long "output"
       <> short 'o'
       <> metavar "FILE"
       <> help "Output file; format is determined by its extension"
        ))
  <*> switch
      ( long "formatted"
     <> help "Preserve document structure; otherwise collapse to plain text"
      )
  <*> switch
      ( long "assets"
     <> help "When reading a PDF, render each page into an assets/ directory"
      )
  <*> optional
      (strOption
        ( long "template"
       <> short 't'
       <> metavar "FILE"
       <> help "LaTeX template file to use when converting to LaTeX"
        ))

parserInfo :: ParserInfo Options
parserInfo = info (optionsParser <**> helper)
  ( fullDesc
 <> progDesc "Convert documents between supported formats"
 <> header "fileforge - document conversion"
  )

main :: IO ()
main = do
  opts <- execParser parserInfo
  catchIOError
    (convertDocument opts)
    (die . ("fileforge: " ++) . show)

convertDocument :: Options -> IO ()
convertDocument opts = do
  let input = inputFile opts
      output = maybe (replaceExtension input "txt")
                     id (outputFile opts)
      isPdf = map toLower (takeExtension input) == ".pdf"

  when (extractAssets opts && not isPdf) $
    die "fileforge: --assets is only supported for PDF input"

  outputFormat <- parseOutputFormat output

  when (isJust (templateFile opts) && outputFormat /= LaTeX) $
    die "fileforge: --template is only supported for LaTeX output"

  inputPath <- canonicalizePath input

  -- canonicalizePath also requires the output to exist.
  -- makeAbsolute would be another option, but resolving existing
  -- output symlinks is important when preventing accidental overwrite.
  outputExists <- doesPathExist output
  outputPath <- if outputExists
    then canonicalizePath output
    else pure output

  when (inputPath == outputPath) $
    die "fileforge: input and output must be different files"

  when (extractAssets opts) $
    extractPdfAssets input (takeDirectory output </> "assets")

  mTemplate <- case templateFile opts of
    Nothing   -> pure Nothing
    Just path -> Just <$> loadLaTeXTemplate path

  result <- runIO $ do
    document <- readDocument input

    outputDocument <- if formatted opts
      then pure document
      else do
        plain <- writePlain def document
        let text = T.unwords (T.words plain)
        pure (Pandoc mempty [Para [Str text]])

    case outputFormat of
      PlainText -> do
        plain <- writePlain def outputDocument
        pure (encodeText plain)

      Docx ->
        writeDocx def outputDocument

      Markdown ->
        encodeText <$> writeMarkdown markdownWriter outputDocument

      LaTeX -> do
        let writerOpts = case mTemplate of
              Just tpl -> def { writerTemplate = Just tpl }
              Nothing  -> def
        encodeText <$> writeLaTeX writerOpts outputDocument

      JSON ->
        encodeText <$> writeJSON def outputDocument

      XML ->
        encodeText <$> writeXML def outputDocument

      PDF -> do
        template <- compileDefaultTemplate (T.pack "latex")
        pdfResult <- makePDF "pdflatex" [] writeLaTeX
          def { writerTemplate = Just template }
          outputDocument
        case pdfResult of
          Left errBytes ->
            liftIO $ die $
              "fileforge: PDF generation failed: "
                ++ T.unpack
                     (TextEncoding.decodeUtf8Lenient (BSL.toStrict errBytes))
          Right pdf ->
            pure pdf

  converted <- either
    (die . ("fileforge: Pandoc error: " ++) . show)
    pure
    result

  BSL.writeFile output converted
  putStrLn $ "Successfully converted: " ++ output

parseOutputFormat :: FilePath -> IO OutputFormat
parseOutputFormat output =
  case map toLower (takeExtension output) of
    ".txt"      -> pure PlainText
    ".docx"     -> pure Docx
    ".md"       -> pure Markdown
    ".markdown" -> pure Markdown
    ".tex"      -> pure LaTeX
    ".json"     -> pure JSON
    ".xml"      -> pure XML
    ".pdf"      -> pure PDF
    _ -> die
      "fileforge: unsupported output format; use .txt, .docx, .md, .markdown, .tex, .json, .xml, or .pdf"

readDocument :: FilePath -> PandocIO Pandoc
readDocument input =
  case map toLower (takeExtension input) of
    ".txt"      -> readMarkdownFile
    ".md"       -> readMarkdownFile
    ".markdown" -> readMarkdownFile

    ".pdf" -> do
      extracted <- liftIO (extractPdf input)
      readMarkdown (def { readerExtensions = pandocExtensions }) extracted

    ".docx" -> do
      bytes <- liftIO (BSL.readFile input)
      readDocx def bytes

    ".tex" -> do
      text <- liftIO (readUtf8File input)
      readLaTeX def text

    ".json" -> do
      text <- liftIO (readUtf8File input)
      readJSON def text

    ".xml" -> do
      text <- liftIO (readUtf8File input)
      readXML def text

    ".xlsx" -> do
      bytes <- liftIO (BSL.readFile input)
      readXlsx def bytes
    ".xlsm" -> do
      bytes <- liftIO (BSL.readFile input)
      readXlsx def bytes

    ".csv" -> do
      bytes <- liftIO (readUtf8File input)
      readCSV def bytes

    _ -> liftIO $ die
      "fileforge: unsupported input format; use .pdf, .docx, .txt, .md, .markdown, .tex, .json, .xml, .xlsx, or .csv"

  where
    readMarkdownFile = do
      text <- liftIO (readUtf8File input)
      readMarkdown
        (def { readerExtensions = pandocExtensions })
        text

readUtf8File :: FilePath -> IO T.Text
readUtf8File path = do
  bytes <- BSL.readFile path
  either
    (\err -> die ("fileforge: invalid UTF-8 in " ++ path ++ ": " ++ show err))
    pure
    (TextEncoding.decodeUtf8' (BSL.toStrict bytes))

encodeText :: T.Text -> BSL.ByteString
encodeText = BSL.fromStrict . TextEncoding.encodeUtf8

markdownWriter :: WriterOptions
markdownWriter = def
  { writerExtensions = pandocExtensions
  }

extractPdf :: FilePath -> IO T.Text
extractPdf input = do
  (exitCode, extracted, stderrText) <-
    readProcessWithExitCode
      "pdftotext"
      ["-layout", "-enc", "UTF-8", input, "-"]
      ""

  case exitCode of
    ExitFailure _ ->
      die ("fileforge: PDF extraction failed: " ++ stderrText)
    ExitSuccess ->
      pure (T.pack extracted)

-- Render each PDF page into assets/page-NNN.png via ImageMagick.
extractPdfAssets :: FilePath -> FilePath -> IO ()
extractPdfAssets input assetsDir = do
  createDirectoryIfMissing True assetsDir
  let pattern = assetsDir </> "page-%03d.png"
  (exitCode, _, stderrText) <-
    readProcessWithExitCode
      "magick"
      ["-density", "150", input, pattern]
      ""

  case exitCode of
    ExitFailure _ ->
      die ("fileforge: PDF asset extraction failed: " ++ stderrText)
    ExitSuccess ->
      putStrLn $ "Extracted PDF assets to: " ++ assetsDir