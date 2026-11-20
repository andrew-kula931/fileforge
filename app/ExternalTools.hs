module ExternalTools
  ( Tool(..)
  , toolBaseName
  , resolveTool
  , getRequiredTool
  , missingToolError
  ) where

import Control.Monad (filterM)
import Data.Char (toLower)
import Data.Maybe (listToMaybe)
import System.Directory (doesFileExist, findExecutable)
import System.Environment (getExecutablePath, lookupEnv)
import System.Exit (die)
import System.FilePath
  ( (</>)
  , (<.>)
  , isAbsolute
  , takeDirectory
  , takeExtension
  )
import qualified System.Info as SysInfo

-- | Supported external helper tools.
data Tool
  = ToolPdfToText
  | ToolMagick
  | ToolPdfEngine FilePath
  deriving (Show, Eq)

-- | Base command name for a tool.
toolBaseName :: Tool -> String
toolBaseName ToolPdfToText        = "pdftotext"
toolBaseName ToolMagick           = "magick"
toolBaseName (ToolPdfEngine name) = name

-- | Human-readable description of what the tool is used for.
toolFeatureDescription :: Tool -> String
toolFeatureDescription ToolPdfToText =
  "Reading and extracting text from PDF files (requires Poppler's 'pdftotext')"
toolFeatureDescription ToolMagick =
  "Rendering PDF pages as image assets via --assets (requires ImageMagick's 'magick')"
toolFeatureDescription (ToolPdfEngine engine) =
  "Generating PDF output via LaTeX engine '" ++ engine ++ "'"

-- | Environment variable specific to the tool, if applicable.
toolEnvVar :: Tool -> Maybe String
toolEnvVar ToolPdfToText        = Just "PDFTOTEXT_PATH"
toolEnvVar ToolMagick           = Just "MAGICK_PATH"
toolEnvVar (ToolPdfEngine _)    = Just "PDF_ENGINE_PATH"

-- | Generate potential candidate file names for a tool on the current OS.
candidateFileNames :: Tool -> [String]
candidateFileNames tool =
  let base = toolBaseName tool
      isWindows = SysInfo.os == "mingw32"
  in if isWindows
       then if map toLower (takeExtension base) == ".exe"
              then [base]
              else [base <.> "exe", base]
       else [base]

-- | Resolve the executable path for a given tool.
--
-- Lookup order:
-- 1. Direct path if tool name is already an absolute or existing file.
-- 2. Explicit directory passed via '--tools-dir' (CLI).
-- 3. Dedicated environment variable (e.g. 'PDFTOTEXT_PATH').
-- 4. General tools directory environment variable ('FILEFORGE_TOOLS_DIR').
-- 5. Portable directories relative to the running fileforge executable:
--      - <exe_dir>/tools/
--      - <exe_dir>/bin/
--      - <exe_dir>/
-- 6. System PATH via 'findExecutable'.
resolveTool :: Maybe FilePath -> Tool -> IO (Either String FilePath)
resolveTool mCliToolsDir tool = do
  let base = toolBaseName tool
      candidates = candidateFileNames tool

  -- 1. Direct file check if base looks like a file path
  if isAbsolute base || '/' `elem` base || '\\' `elem` base
    then do
      exists <- doesFileExist base
      if exists
        then pure (Right base)
        else pure (Left (missingToolError tool ["Explicit path: " ++ base]))
    else do
      -- 2. Check CLI --tools-dir
      mCliFound <- checkDirCandidates mCliToolsDir candidates

      -- 3. Check tool-specific environment variable
      mToolEnvFound <- case toolEnvVar tool of
        Nothing -> pure Nothing
        Just var -> do
          mVal <- lookupEnv var
          case mVal of
            Just path -> do
              exists <- doesFileExist path
              pure (if exists then Just path else Nothing)
            Nothing -> pure Nothing

      -- 4. Check FILEFORGE_TOOLS_DIR environment variable
      mEnvDir <- lookupEnv "FILEFORGE_TOOLS_DIR"
      mEnvDirFound <- checkDirCandidates mEnvDir candidates

      -- 5. Check sibling directories relative to fileforge executable
      exePath <- getExecutablePath
      let exeDir = takeDirectory exePath
          siblingDirs =
            [ exeDir </> "tools"
            , exeDir </> "bin"
            , exeDir
            ]
      mSiblingFound <- firstExistingInDirs siblingDirs candidates

      -- 6. Check system PATH
      mPathFound <- findOnSystemPath candidates

      let mFinalPath =
            mCliFound
              `mplusMaybe` mToolEnvFound
              `mplusMaybe` mEnvDirFound
              `mplusMaybe` mSiblingFound
              `mplusMaybe` mPathFound

      case mFinalPath of
        Just resolved -> pure (Right resolved)
        Nothing -> do
          let checkedLocations =
                [ maybe "CLI --tools-dir: (not specified)" (\d -> "CLI --tools-dir: " ++ d) mCliToolsDir
                , maybe "Tool env var: (not set)" (\v -> "Tool env var: " ++ v) (toolEnvVar tool)
                , maybe "Env var FILEFORGE_TOOLS_DIR: (not set)" (\d -> "Env var FILEFORGE_TOOLS_DIR: " ++ d) mEnvDir
                , "Portable sibling dirs: " ++ exeDir </> "tools, bin"
                , "System PATH"
                ]
          pure (Left (missingToolError tool checkedLocations))

  where
    mplusMaybe :: Maybe a -> Maybe a -> Maybe a
    mplusMaybe (Just a) _ = Just a
    mplusMaybe Nothing mb = mb

    checkDirCandidates :: Maybe FilePath -> [String] -> IO (Maybe FilePath)
    checkDirCandidates Nothing _ = pure Nothing
    checkDirCandidates (Just dir) fileNames = do
      let paths = [dir </> f | f <- fileNames]
      existing <- filterM doesFileExist paths
      pure (listToMaybe existing)

    firstExistingInDirs :: [FilePath] -> [String] -> IO (Maybe FilePath)
    firstExistingInDirs dirs fileNames = do
      let allPaths = [d </> f | d <- dirs, f <- fileNames]
      existing <- filterM doesFileExist allPaths
      pure (listToMaybe existing)

    findOnSystemPath :: [String] -> IO (Maybe FilePath)
    findOnSystemPath [] = pure Nothing
    findOnSystemPath (f:fs) = do
      mFound <- findExecutable f
      case mFound of
        Just p  -> pure (Just p)
        Nothing -> findOnSystemPath fs

-- | Get required tool or terminate process with an actionable error.
getRequiredTool :: Maybe FilePath -> Tool -> IO FilePath
getRequiredTool mToolsDir tool = do
  result <- resolveTool mToolsDir tool
  case result of
    Right path  -> pure path
    Left errMsg -> die errMsg

-- | Format an informative, actionable error message when a tool is missing.
missingToolError :: Tool -> [String] -> String
missingToolError tool checkedLocs = unlines $
  [ "fileforge: external tool '" ++ toolBaseName tool ++ "' is required but was not found."
  , ""
  , "Purpose:"
  , "  " ++ toolFeatureDescription tool
  , ""
  , "Locations searched:"
  ]
  ++ map ("  - " ++) checkedLocs
  ++
  [ ""
  , "How to resolve:"
  , "  On Windows:"
  , "    1. Zero-Install Portable (Recommended):"
  , "       Run 'powershell -ExecutionPolicy Bypass -File scripts/fetch-tools.ps1'"
  , "       or copy '" ++ toolBaseName tool ++ ".exe' into a 'tools' folder next to fileforge.exe."
  , "    2. Winget package manager:"
  , "       winget install " ++ wingetPackage tool
  , "    3. Or specify custom directory via --tools-dir / -T or FILEFORGE_TOOLS_DIR."
  , "  On Arch Linux:"
  , "    sudo pacman -S " ++ pacmanPackage tool
  ]
  where
    wingetPackage ToolPdfToText        = "poppler"
    wingetPackage ToolMagick           = "ImageMagick.ImageMagick"
    wingetPackage (ToolPdfEngine _)    = "MiKTeX.MiKTeX (or Tectonic.Tectonic)"

    pacmanPackage ToolPdfToText        = "poppler"
    pacmanPackage ToolMagick           = "imagemagick"
    pacmanPackage (ToolPdfEngine _)    = "texlive-basic (or tectonic)"
