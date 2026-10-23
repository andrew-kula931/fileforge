module Main where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString.Lazy as BSL
import Data.Char (toLower)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TextEncoding
import Options.Applicative
import System.Directory (canonicalizePath)
import System.Exit (die, ExitCode(..))
import System.FilePath (replaceExtension, takeExtension)
import System.IO.Error (catchIOError)
import System.Process (readProcessWithExitCode)
import Text.Pandoc
  ( def
  , Pandoc(..)
  , PandocIO
  , Block(..)
  , Inline(..)
  , ReaderOptions(..)
  , WriterOptions(..)
  , pandocExtensions
  , readDocx
  , readMarkdown
  , writeDocx
  , writeMarkdown
  , writePlain
  , runIO
  )

data Options = Options
  { inputFile  :: FilePath
  , outputFile :: Maybe FilePath
  , formatted  :: Bool
  } deriving (Show)

data OutputFormat = PlainText | Docx | Markdown

optionsParser :: Parser Options
optionsParser = Options
  <$> strOption
      ( long "input"
     <> short 'i'
     <> metavar "FILE"
     <> help "Input PDF, DOCX, or Markdown (.md or .markdown) file"
      )
  <*> optional
      (strOption
        ( long "output"
       <> short 'o'
       <> metavar "FILE"
       <> help "Output .txt, .docx, .md, or .markdown file (default: input path with .txt extension)"
        ))
  <*> switch
      ( long "formatted"
     <> help "Preserve document structure; otherwise collapse to plain text"
      )

parserInfo :: ParserInfo Options
parserInfo = info (optionsParser <**> helper)
  ( fullDesc
 <> progDesc "Convert PDF, DOCX, and Markdown to text, DOCX, or Markdown"
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
  outputPath <- canonicalizePath output

  when (inputPath == outputPath) $
    die "fileforge: input and output must be different files"

  outputFormat <- case map toLower (takeExtension output) of
    ".txt" -> pure PlainText
    ".docx" -> pure Docx
    ".md" -> pure Markdown
    ".markdown" -> pure Markdown
    _ -> die "fileforge: unsupported output format; use .txt, .docx, .md, or .markdown"

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
        plain <- writePlain def document
        pure (encodeText (if formatted opts then plain else T.unwords (T.words plain)))
      Docx -> writeDocx def outputDocument
      Markdown -> encodeText <$> writeMarkdown markdownWriter outputDocument
  converted <- either (die . ("fileforge: Pandoc error: " ++) . show) pure result
  BSL.writeFile output converted

  putStrLn $ "Successfully converted: " ++ output

readDocument :: FilePath -> PandocIO Pandoc
readDocument input =
  case map toLower (takeExtension input) of
    ".txt" -> readMarkdownFile
    ".pdf" -> do
      extracted <- liftIO (extractPdf input)
      readMarkdown def extracted
    ".docx" -> do
      bytes <- liftIO (BSL.readFile input)
      readDocx def bytes
    ".md" -> readMarkdownFile
    ".markdown" -> readMarkdownFile
    _ -> liftIO $ die "fileforge: unsupported input format; use .pdf, .docx, .txt, .md, or .markdown"
  where
    readMarkdownFile = do
      bytes <- liftIO (BSL.readFile input)
      text <- liftIO $ either (die . ("fileforge: invalid UTF-8 Markdown: " ++) . show)
                              pure (TextEncoding.decodeUtf8' (BSL.toStrict bytes))
      readMarkdown (def { readerExtensions = pandocExtensions }) text

encodeText :: T.Text -> BSL.ByteString
encodeText = BSL.fromStrict . TextEncoding.encodeUtf8

markdownWriter :: WriterOptions
markdownWriter = def { writerExtensions = pandocExtensions }

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
    ExitSuccess -> pure (T.pack extracted)
