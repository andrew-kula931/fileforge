{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception (bracket)
import Control.Monad (forM_, unless, when)
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy as BSL
import Data.List (isInfixOf)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( canonicalizePath, createDirectory, createFileLink, doesDirectoryExist
  , getTemporaryDirectory, listDirectory, removeDirectoryRecursive, removeFile
  )
import System.Exit (ExitCode(..))
import System.FilePath ((</>), replaceExtension, takeExtension)
import System.IO (hClose, openTempFile)
import System.IO.Error (catchIOError)
import System.Process (readProcessWithExitCode)
import Text.Pandoc
  ( Block(..), Inline(..), Pandoc(..), PandocIO, ReaderOptions(..), def
  , pandocExtensions, readDocx, readMarkdown, runIO, writeDocx, writePlain
  )

main :: IO ()
main = bracket temporaryDirectory removeDirectoryRecursive $ \dir -> do
  let markdown = dir </> "source.md"
      docx = dir </> "source.docx"
      pdf = dir </> "source.pdf"
      sourceText = "# Heading\n\nFirst *emphasized* paragraph.\n\nSecond paragraph: caf\233.\n\n- First item\n- Second item\n"
  TIO.writeFile markdown sourceText
  document <- fromPandoc $ readMarkdown markdownReader sourceText
  docxBytes <- fromPandoc $ writeDocx def document
  BSL.writeFile docx docxBytes
  BS.writeFile pdf samplePdf

  forM_ [markdown, docx, pdf] $ \input ->
    forM_ ["txt", "md", "docx"] $ \extension ->
      forM_ [False, True] $ \formatted -> do
        let output = dir </> ("output." ++ extension)
            flags = if formatted then ["--formatted"] else []
        expectSuccess (["-i", input, "-o", output] ++ flags)
        outputDocument <- case extension of
          "docx" -> do
            bytes <- BSL.readFile output
            fromPandoc (readDocx def bytes)
          "md" -> do
            text <- TIO.readFile output
            fromPandoc (readMarkdown markdownReader text)
          _ -> do
            text <- TIO.readFile output
            whenPlain formatted text
            pure (Pandoc mempty [Para [Str text]])
        plain <- fromPandoc (writePlain def outputDocument)
        let expected = if input == pdf
              then "Hello world Second paragraph"
              else "Heading First emphasized paragraph. Second paragraph: caf\233. - First item - Second item"
        assert ("content preserved: " ++ show (input, extension, formatted)) $
          normalize plain == expected
        unless (input == pdf || extension == "txt") $ do
          assert "headings follow --formatted" (hasHeading outputDocument == formatted)
          assert "lists follow --formatted" (hasList outputDocument == formatted)
          assert "emphasis follows --formatted" (hasEmphasis outputDocument == formatted)
        unless (input == pdf || extension /= "txt" || not formatted) $ do
          text <- TIO.readFile output
          assert "formatted text retains paragraph breaks" ("\n\n" `T.isInfixOf` text)

  expectSuccess ["-i", markdown]
  defaultText <- TIO.readFile (replaceExtension markdown "txt")
  assert "default output is plain text" $
    T.stripEnd defaultText
      == "Heading First emphasized paragraph. Second paragraph: caf\233. - First item - Second item"

  let upperInput = dir </> "upper.MARKDOWN"
      upperOutput = dir </> "upper.DOCX"
      aliasOutput = dir </> "alias.MARKDOWN"
  TIO.writeFile upperInput sourceText
  expectSuccess ["-i", upperInput, "-o", upperOutput, "--formatted"]
  expectSuccess ["-i", upperOutput, "-o", aliasOutput, "--formatted"]
  aliasText <- TIO.readFile aliasOutput
  aliasDocument <- fromPandoc (readMarkdown markdownReader aliasText)
  assert "extensions are case-insensitive and .markdown is supported" (hasHeading aliasDocument)

  expectFailure [] "--input"
  expectFailure ["-i", markdown, "-o", markdown] "different files"
  let link = dir </> "link.md"
  absoluteInput <- canonicalizePath markdown
  canSymlink <- catchIOError
    (createFileLink absoluteInput link >> pure True)
    (\_ -> pure False)
  when canSymlink $
    expectFailure ["-i", markdown, "-o", link] "different files"
  original <- TIO.readFile markdown
  assert "input remains untouched" (original == sourceText)

  expectFailure ["-i", dir </> "missing.md"] "fileforge:"
  expectFailure ["-i", dir </> "unsupported.xyz"] "unsupported input format"
  let output = dir </> "protected.txt"
      invalidDocx = dir </> "invalid.docx"
      invalidPdf = dir </> "invalid.pdf"
  TIO.writeFile output "existing content"
  BS.writeFile invalidDocx "not a DOCX"
  BS.writeFile invalidPdf "not a PDF"
  forM_ [invalidDocx, invalidPdf] $ \input -> do
    expectFailure ["-i", input, "-o", output] "fileforge:"
    unchanged <- TIO.readFile output
    assert "failed reads preserve output" (unchanged == "existing content")
  let invalidMarkdown = dir </> "invalid.md"
  BS.writeFile invalidMarkdown (BS.pack "\255")
  expectFailure ["-i", invalidMarkdown, "-o", output] "invalid UTF-8"
  expectFailure ["-i", markdown, "-o", dir </> "unsupported.xyz"] "output format"
  expectFailure ["-i", markdown, "-o", dir </> "missing" </> "output.md"] "fileforge:"
  expectFailure ["-i", markdown, "-o", dir </> "no-assets.txt", "--assets"]
    "--assets is only supported for PDF input"

  let assetsOutput = dir </> "with-assets.txt"
      assetsDir = dir </> "assets"
  expectSuccess ["-i", pdf, "-o", assetsOutput, "--assets"]
  assert "assets directory is created" =<< doesDirectoryExist assetsDir
  assetFiles <- listDirectory assetsDir
  assert "assets directory contains rendered pages" $
    not (null assetFiles) && all ((== ".png") . takeExtension) assetFiles

  let exportedPdf = dir </> "exported.pdf"
  expectSuccess ["-i", markdown, "-o", exportedPdf, "--formatted"]
  exportedText <- extractPdfText exportedPdf
  let exportedPlain = normalize exportedText
  forM_
    [ "Heading"
    , "First emphasized paragraph."
    , "Second paragraph: caf\233."
    , "First item"
    , "Second item"
    ] $ \snippet ->
      assert ("PDF export preserves content: " ++ T.unpack snippet)
        (snippet `T.isInfixOf` exportedPlain)

  let ieeeTemplate = "app/examples/ieee_template.tex"
      outputTex = dir </> "templated_ieee.tex"
  expectSuccess ["-i", markdown, "-o", outputTex, "--template", ieeeTemplate, "--formatted"]
  ieeeContent <- TIO.readFile outputTex
  assert "IEEE template has documentclass" ("\\documentclass[conference]{IEEEtran}" `T.isInfixOf` ieeeContent)
  assert "IEEE template preserves heading" ("Heading" `T.isInfixOf` ieeeContent)
  assert "IEEE template preserves paragraph" ("caf\233" `T.isInfixOf` ieeeContent)
  assert "IEEE template preserves items" ("First item" `T.isInfixOf` ieeeContent)

  let unformattedTex = dir </> "unformatted_ieee.tex"
  expectSuccess ["-i", markdown, "-o", unformattedTex, "--template", ieeeTemplate]
  unformattedContent <- TIO.readFile unformattedTex
  assert "Unformatted IEEE template has documentclass" ("\\documentclass[conference]{IEEEtran}" `T.isInfixOf` unformattedContent)
  assert "Unformatted IEEE template has flattened text" ("Heading First emphasized paragraph." `T.isInfixOf` unformattedContent)

  let rawTemplate = dir </> "raw_template.tex"
      rawOutputTex = dir </> "templated_raw.tex"
  TIO.writeFile rawTemplate "\\documentclass{article}\n\\begin{document}\n% Custom Raw Preamble Notice\n\\end{document}\n"
  expectSuccess ["-i", markdown, "-o", rawOutputTex, "-t", rawTemplate, "--formatted"]
  rawContent <- TIO.readFile rawOutputTex
  assert "Raw template preamble preserved" ("Custom Raw Preamble Notice" `T.isInfixOf` rawContent)
  assert "Raw template has injected heading" ("Heading" `T.isInfixOf` rawContent)
  assert "Raw template has injected paragraph" ("caf\233" `T.isInfixOf` rawContent)

  let defaultTex = dir </> "fragment.tex"
  expectSuccess ["-i", markdown, "-o", defaultTex, "--formatted"]
  fragmentContent <- TIO.readFile defaultTex
  assert "Default LaTeX has no documentclass" (not ("\\documentclass" `T.isInfixOf` fragmentContent))
  assert "Default LaTeX has section" ("\\section{Heading}" `T.isInfixOf` fragmentContent)

  expectFailure ["-i", markdown, "-o", dir </> "invalid.docx", "--template", ieeeTemplate]
    "--template is only supported for LaTeX output"
  expectFailure ["-i", markdown, "-o", dir </> "invalid.pdf", "--template", ieeeTemplate]
    "--template is only supported for LaTeX output"
  expectFailure ["-i", markdown, "-o", dir </> "missing.tex", "--template", dir </> "nonexistent.tex"]
    "template file does not exist"

  expectFailure
    ["-i", markdown, "-o", dir </> "custom_engine.pdf", "--pdf-engine", "nonexistent-engine"]
    "external tool 'nonexistent-engine' is required but was not found"

  putStrLn "All document conversion CLI tests passed."
  where
    normalize = T.unwords . T.words
    whenPlain formatted text =
      unless formatted $
        assert "unformatted text has collapsed whitespace"
          (T.stripEnd text == normalize text)

markdownReader :: ReaderOptions
markdownReader = def { readerExtensions = pandocExtensions }

hasHeading :: Pandoc -> Bool
hasHeading (Pandoc _ blocks) = any isHeading blocks
  where
    isHeading (Header _ _ _) = True
    isHeading _ = False

hasList :: Pandoc -> Bool
hasList (Pandoc _ blocks) = any isList blocks
  where
    isList (BulletList _) = True
    isList _ = False

hasEmphasis :: Pandoc -> Bool
hasEmphasis (Pandoc _ blocks) = any emphasized blocks
  where
    emphasized (Para inlines) = any isEmphasis inlines
    emphasized _ = False
    isEmphasis (Emph _) = True
    isEmphasis _ = False

assert :: String -> Bool -> IO ()
assert message condition = unless condition (ioError (userError message))

expectSuccess :: [String] -> IO ()
expectSuccess args = do
  (code, _, err) <- readProcessWithExitCode "fileforge" args ""
  assert ("command failed: " ++ show args ++ "\n" ++ err) (code == ExitSuccess)

expectFailure :: [String] -> String -> IO ()
expectFailure args message = do
  (code, _, err) <- readProcessWithExitCode "fileforge" args ""
  assert ("expected failure: " ++ show args) (code /= ExitSuccess)
  assert ("missing error message: " ++ err) (message `isInfixOf` err)

fromPandoc :: PandocIO a -> IO a
fromPandoc action = do
  result <- runIO action
  either (ioError . userError . show) pure result

temporaryDirectory :: IO FilePath
temporaryDirectory = do
  root <- getTemporaryDirectory
  (path, handle) <- openTempFile root "fileforge-cli"
  hClose handle
  removeFile path
  createDirectory path
  pure path

extractPdfText :: FilePath -> IO T.Text
extractPdfText input = do
  (code, extracted, err) <-
    readProcessWithExitCode
      "pdftotext"
      ["-layout", "-enc", "UTF-8", input, "-"]
      ""
  assert ("pdftotext failed: " ++ err) (code == ExitSuccess)
  pure (T.pack extracted)

samplePdf :: BS.ByteString
samplePdf = BS.pack $ header ++ concat objects ++ xref ++ trailer
  where
    header = "%PDF-1.4\n"
    stream = "BT /F1 12 Tf 72 720 Td (Hello world) Tj 0 -60 Td (Second paragraph) Tj ET\n"
    contents =
      [ "<< /Type /Catalog /Pages 2 0 R >>"
      , "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
      , "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
          ++ "/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
      , "<< /Length " ++ show (length stream) ++ " >>\nstream\n" ++ stream ++ "endstream"
      , "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
      ]
    objects = zipWith (\n body -> show n ++ " 0 obj\n" ++ body ++ "\nendobj\n")
                      [1 :: Int ..] contents
    offsets = scanl (+) (length header) (map length objects)
    entry offset =
      let digits = show offset
      in replicate (10 - length digits) '0' ++ digits ++ " 00000 n \n"
    xref = "xref\n0 6\n0000000000 65535 f \n" ++ concatMap entry (take 5 offsets)
    trailer = "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n"
              ++ show (last offsets) ++ "\n%%EOF\n"
