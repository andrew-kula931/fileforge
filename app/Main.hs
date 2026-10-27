module Main where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString.Lazy as BSL
import Data.Char (toLower)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TextEncoding
import Options.Applicative
import System.Directory (canonicalizePath, doesPathExist)
import System.Exit (die, ExitCode(..))
import System.FilePath (replaceExtension, takeExtension)
import System.IO.Error (catchIOError)
import System.Process (readProcessWithExitCode)
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

data Options = Options
  { inputFile  :: FilePath
  , outputFile :: Maybe FilePath
  , formatted  :: Bool
  } deriving (Show)

data OutputFormat
  = PlainText
  | Docx
  | Markdown
  | LaTeX
  | JSON
  | XML
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

  outputFormat <- parseOutputFormat output

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

      LaTeX ->
        encodeText <$> writeLaTeX def outputDocument

      JSON ->
        encodeText <$> writeJSON def outputDocument

      XML ->
        encodeText <$> writeXML def outputDocument

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
    _ -> die
      "fileforge: unsupported output format; use .txt, .docx, .md, .markdown, .tex, .json, or .xml"

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