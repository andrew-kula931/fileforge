module Main where

import Control.Monad (when)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Options.Applicative
import System.Directory (canonicalizePath, makeAbsolute)
import System.Exit (die, ExitCode(..))
import System.FilePath (replaceExtension)
import System.IO.Error (catchIOError)
import System.Process (readProcessWithExitCode)
import Text.Pandoc
  ( def
  , readMarkdown
  , writePlain
  , runPure
  )

data Options = Options
  { inputFile  :: FilePath
  , outputFile :: Maybe FilePath
  , formatted  :: Bool
  } deriving (Show)

optionsParser :: Parser Options
optionsParser = Options
  <$> strOption
      ( long "input"
     <> short 'i'
     <> metavar "FILE"
     <> help "Input PDF file"
      )
  <*> optional
      (strOption
        ( long "output"
       <> short 'o'
       <> metavar "FILE"
       <> help "Output text file"
        ))
  <*> switch
      ( long "formatted"
     <> help "Preserve paragraph structure"
      )

parserInfo :: ParserInfo Options
parserInfo = info (optionsParser <**> helper)
  ( fullDesc
 <> progDesc "Convert PDF documents to UTF-8 text using Pandoc"
 <> header "fileforge - PDF to text conversion"
  )

main :: IO ()
main = do
  opts <- execParser parserInfo
  catchIOError
    (convertPdf opts)
    (die . ("fileforge: " ++) . show)

convertPdf :: Options -> IO ()
convertPdf opts = do
  let input = inputFile opts
      output = maybe (replaceExtension input "txt")
                     id (outputFile opts)

  inputPath <- canonicalizePath input
  outputPath <- makeAbsolute output

  when (inputPath == outputPath) $
    die "fileforge: input and output must be different files"

  -- Extract text from PDF using Poppler.
  (exitCode, extracted, stderrText) <-
    readProcessWithExitCode
      "pdftotext"
      ["-layout", "-enc", "UTF-8", input, "-"]
      ""

  case exitCode of
    ExitFailure _ ->
      die ("fileforge: PDF extraction failed: " ++ stderrText)
    ExitSuccess -> pure ()

  -- Convert extracted text through Pandoc.
  let result = runPure $ do
        document <- readMarkdown def (T.pack extracted)
        writePlain def document

  pandocText <- either
    (die . ("fileforge: Pandoc error: " ++) . show)
    pure
    result

  -- Optionally collapse whitespace.
  let outputText =
        if formatted opts
          then pandocText
          else T.unwords (T.words pandocText)

  TIO.writeFile output outputText

  putStrLn $ "Successfully converted: " ++ output
