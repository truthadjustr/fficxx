{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
-----------------------------------------------------------------------------
-- |
-- Module      : FFICXX.Generate.Code.Cabal
-- Copyright   : (c) 2011-2018 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--
-----------------------------------------------------------------------------

module FFICXX.Generate.Code.Cabal where

import Data.Aeson.Encode.Pretty    (encodePretty)
import qualified Data.ByteString.Lazy as BL
import Data.List                   (nub)
import Data.Monoid                 ((<>))
import Data.Text                   (Text)
import Data.Text.Template          (substitute)
import qualified Data.Text as T    (intercalate,pack,replicate,unlines)
import qualified Data.Text.Lazy as TL (toStrict)
import qualified Data.Text.IO as TIO (writeFile)
import System.FilePath             ((<.>),(</>))
--
import FFICXX.Generate.Type.Cabal  (AddCInc(..),AddCSrc(..)
                                   ,CabalName(..),Cabal(..)
                                   ,GeneratedCabalInfo(..))
import FFICXX.Generate.Type.Module
import FFICXX.Generate.Type.PackageInterface
import FFICXX.Generate.Util


cabalIndentation :: Text -- String
cabalIndentation = T.replicate 23 " "


unlinesWithIndent = T.unlines . map (cabalIndentation <>)

-- for source distribution
genCsrcFiles :: (TopLevelImportHeader,[ClassModule])
             -> [AddCInc]
             -> [AddCSrc]
             -> [String]
genCsrcFiles (tih,cmods) acincs acsrcs =
  let -- indent = cabalIndentation
      selfheaders' = do
        x <- cmods
        y <- cmCIH x
        return (cihSelfHeader y)
      selfheaders = nub selfheaders'
      selfcpp' = do
        x <- cmods
        y <- cmCIH x
        return (cihSelfCpp y)
      selfcpp = nub selfcpp'
      tlh = tihHeaderFileName tih <.> "h"
      tlcpp = tihHeaderFileName tih <.> "cpp"
      includeFileStrsWithCsrc = map (\x->"csrc"</> x) $
                                 (if (null.tihFuncs) tih then map unHdrName selfheaders else tlh:(map unHdrName selfheaders))
                                 ++ map (\(AddCInc hdr _) -> hdr) acincs
      cppFilesWithCsrc = map (\x->"csrc"</>x)  $
                           (if (null.tihFuncs) tih then selfcpp else tlcpp:selfcpp)
                           ++ map (\(AddCSrc src _) -> src) acsrcs


  in includeFileStrsWithCsrc <> cppFilesWithCsrc

-- for library
genIncludeFiles :: String        -- ^ package name
                -> ([ClassImportHeader],[TemplateClassImportHeader])
                -> [AddCInc]
                -> [String]
genIncludeFiles pkgname (cih,tcih) acincs =
  let -- indent = cabalIndentation
      selfheaders = map cihSelfHeader cih <> map tcihSelfHeader tcih
      includeFileStrs = map unHdrName (selfheaders ++ map (\(AddCInc hdr _) -> HdrName hdr) acincs)
  in (pkgname<>"Type.h") : includeFileStrs


--     unlines ((indent<>


-- for library
genCppFiles :: (TopLevelImportHeader,[ClassModule])
            -> [AddCSrc]
            -> [String]
genCppFiles (tih,cmods) acsrcs =
  let -- indent = cabalIndentation
      selfcpp' = do
        x <- cmods
        y <- cmCIH x
        return (cihSelfCpp y)
      selfcpp = nub selfcpp'
      tlcpp = tihHeaderFileName tih <.> "cpp"
      cppFileStrs = map (\x -> "csrc" </> x)  $
                      (if (null.tihFuncs) tih then selfcpp else tlcpp:selfcpp)
                      ++ map (\(AddCSrc src _) -> src) acsrcs
  in cppFileStrs



-- | generate exposed module list in cabal file
genExposedModules :: String -> ([ClassModule],[TemplateClassModule]) -> [String]
genExposedModules summarymod (cmods,tmods) =
    let -- indentspace = cabalIndentation
        -- summarystrs = summarymod
        cmodstrs = map cmModule cmods
        rawType = map ((\x -> x <> ".RawType").cmModule) cmods
        ffi = map ((\x -> x <> ".FFI").cmModule) cmods
        interface= map ((\x-> x <> ".Interface").cmModule) cmods
        cast = map ((\x-> x <> ".Cast").cmModule) cmods
        implementation = map ((\x-> x <> ".Implementation").cmModule) cmods
        template = map ((\x-> x <> ".Template").tcmModule) tmods
        th = map ((\x-> x <> ".TH").tcmModule) tmods
    in  -- unlines
        [summarymod]<>cmodstrs<>rawType<>ffi<>interface<>cast<>implementation<>template<>th

-- | generate other modules in cabal file
genOtherModules :: [ClassModule] -> [String]
genOtherModules _cmods = [""]

-- | generate additional package dependencies.
genPkgDeps :: [CabalName] -> [String]
genPkgDeps cs =    [ "base > 4 && < 5"
                   , "fficxx >= 0.5"
                   , "fficxx-runtime >= 0.5"
                   , "template-haskell"
                   ]
                ++ map unCabalName cs



-- |
cabalTemplate :: Text
cabalTemplate =
  "Name:                $pkgname\n\
  \Version:     $version\n\
  \Synopsis:    $synopsis\n\
  \Description:         $description\n\
  \Homepage:       $homepage\n\
  \$licenseField\n\
  \$licenseFileField\n\
  \Author:              $author\n\
  \Maintainer:  $maintainer\n\
  \Category:       $category\n\
  \Tested-with:    GHC >= 7.6\n\
  \Build-Type:  $buildtype\n\
  \cabal-version:  >=1.10\n\
  \Extra-source-files:\n\
  \$extraFiles\n\
  \$csrcFiles\n\
  \\n\
  \$sourcerepository\n\
  \\n\
  \Library\n\
  \  default-language: Haskell2010\n\
  \  hs-source-dirs: src\n\
  \  ghc-options:  -Wall -funbox-strict-fields -fno-warn-unused-do-bind -fno-warn-orphans -fno-warn-unused-imports\n\
  \  ghc-prof-options: -caf-all -auto-all\n\
  \  cc-options: $ccOptions\n\
  \  Build-Depends: $pkgdeps\n\
  \  Exposed-Modules:\n\
  \$exposedModules\n\
  \  Other-Modules:\n\
  \$otherModules\n\
  \  extra-lib-dirs: $extralibdirs\n\
  \  extra-libraries:    stdc++ $extraLibraries\n\
  \  Include-dirs:       csrc $extraincludedirs\n\
  \  pkgconfig-depends: $pkgconfigDepends\n\
  \  Install-includes:\n\
  \$includeFiles\n\
  \  C-sources:\n\
  \$cppFiles\n"



-- TODO: remove all T.pack after we switch over to Text
genCabalInfo
  :: Cabal
  -> String
  -> PackageConfig
  -> [String] -- ^ extra libs
  -> GeneratedCabalInfo
genCabalInfo cabal summarymodule pkgconfig extralibs =
  let tih = pcfg_topLevelImportHeader pkgconfig
      classmodules = pcfg_classModules pkgconfig
      cih = pcfg_classImportHeaders pkgconfig
      tmods = pcfg_templateClassModules pkgconfig
      tcih = pcfg_templateClassImportHeaders pkgconfig
      acincs = pcfg_additional_c_incs pkgconfig
      acsrcs = pcfg_additional_c_srcs pkgconfig
      extrafiles = cabal_extrafiles cabal
  in GeneratedCabalInfo {
       gci_pkgname          = T.pack (unCabalName (cabal_pkgname cabal))
     , gci_version          = T.pack (cabal_version cabal)
     , gci_synopsis         = ""
     , gci_description      = ""
     , gci_homepage         = ""
     , gci_license          = maybe "" T.pack (cabal_license cabal)
     , gci_licenseFile      = maybe "" T.pack (cabal_licensefile cabal)
     , gci_author           = ""
     , gci_maintainer       = ""
     , gci_category         = ""
     , gci_buildtype        = "Simple"
     , gci_extraFiles       = map T.pack extrafiles
     , gci_csrcFiles        = map T.pack $ genCsrcFiles (tih,classmodules) acincs acsrcs
     , gci_sourcerepository = ""
     , gci_ccOptions        = ["-std=c++14"]
     , gci_pkgdeps          = map T.pack $ genPkgDeps (cabal_additional_pkgdeps cabal)
     , gci_exposedModules   = map T.pack $ genExposedModules summarymodule (classmodules,tmods)
     , gci_otherModules     = map T.pack $ genOtherModules classmodules
     , gci_extraLibDirs     = map T.pack $ cabal_extralibdirs cabal
     , gci_extraLibraries   = map T.pack extralibs
     , gci_extraIncludeDirs = map T.pack $ cabal_extraincludedirs cabal
     , gci_pkgconfigDepends = map T.pack $ cabal_pkg_config_depends cabal
     , gci_includeFiles     = map T.pack $ genIncludeFiles (unCabalName (cabal_pkgname cabal)) (cih,tcih) acincs
     , gci_cppFiles         = map T.pack $ genCppFiles (tih,classmodules) acsrcs
     }


genCabalFile :: GeneratedCabalInfo -> Text
genCabalFile GeneratedCabalInfo {..} =
  TL.toStrict $
    substitute cabalTemplate $
      contextT [ ("licenseField"    , "license: " <> gci_license)
               , ("licenseFileField", "license-file: " <> gci_licenseFile)
               , ("pkgname"         , gci_pkgname)
               , ("version"         , gci_version)
               , ("buildtype"       , gci_buildtype)
               , ("synopsis"        , gci_synopsis)
               , ("description"     , gci_description)
               , ("homepage"        , gci_homepage)
               , ("author"          , gci_author)
               , ("maintainer"      , gci_maintainer)
               , ("category"        , gci_category)
               , ("sourcerepository", gci_sourcerepository)
               , ("ccOptions"       , T.intercalate " " gci_ccOptions)
               , ("pkgdeps"         , T.intercalate ", " gci_pkgdeps)
               , ("extraFiles"      , unlinesWithIndent gci_extraFiles)
               , ("csrcFiles"       , unlinesWithIndent gci_csrcFiles)
               , ("includeFiles"    , unlinesWithIndent gci_includeFiles)
               , ("cppFiles"        , unlinesWithIndent gci_cppFiles)
               , ("exposedModules"  , unlinesWithIndent gci_exposedModules)
               , ("otherModules"    , unlinesWithIndent gci_otherModules)
               , ("extralibdirs"    , T.intercalate ", " gci_extraLibDirs)
               , ("extraincludedirs", T.intercalate ", " gci_extraIncludeDirs)
               , ("extraLibraries"  , T.intercalate ", " gci_extraLibraries)
               , ("cabalIndentation", cabalIndentation)
               , ("pkgconfigDepends", T.intercalate ", " gci_pkgconfigDepends)
               ]


-- |
buildCabalFile
  :: Cabal
  -> String
  -> PackageConfig
  -> [String]      -- ^ Extra libs
  -> FilePath      -- ^ Cabal file path
  -> IO ()
buildCabalFile cabal summarymodule pkgconfig extralibs cabalfile = do
  let
      cinfo = genCabalInfo cabal summarymodule pkgconfig extralibs
      txt = genCabalFile cinfo
  TIO.writeFile cabalfile txt


-- |
buildJSONFile
  :: Cabal
  -> String
  -> PackageConfig
  -> [String]      -- ^ Extra libs
  -> FilePath      -- ^ JSON file path
  -> IO ()
buildJSONFile cabal summarymodule pkgconfig extralibs jsonfile = do
  let cinfo = genCabalInfo cabal summarymodule pkgconfig extralibs
  BL.writeFile jsonfile (encodePretty cinfo)
