{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE CPP #-}

module Web.Apiary.PureScript.Internal where

import qualified System.FilePath.Glob as G

import qualified Language.PureScript as P

import Control.Monad.Apiary.Action(ActionT, contentType, appendString, appendBytes, string, bytes)
import Control.Monad.Trans.Reader(runReaderT)
import Control.Exception(Exception, throwIO, try)
import Control.Applicative((<$>))

import Web.Apiary(MonadIO(..))
import Data.Apiary.Extension(Extension)

import Data.Default.Class(Default(def))
import Data.IORef(IORef, newIORef, readIORef, atomicModifyIORef')
import Data.Typeable(Typeable)
import qualified Data.HashMap.Strict as H
import qualified Text.Parsec.Error as P

data PureScriptException
    = ParseError   P.ParseError
    | CompileError String
    deriving (Show, Typeable)
instance Exception PureScriptException

defaultPatterns :: [G.Pattern]
defaultPatterns = map G.compile 
    [ "src/**/*.purs"
    , "bower_components/purescript-*/src/**/*.purs"
    ]

data PureScriptConfig = PureScriptConfig
    { libraryPatterns   :: [G.Pattern]
    , libraryBaseDir    :: FilePath
    , development       :: Bool
    , initialCompiles   :: [FilePath]
    , pureScriptPrefix  :: [String]
    , pureScriptOptions :: P.Options P.Compile
    }

instance Default PureScriptConfig where
    def = PureScriptConfig 
        defaultPatterns
        "."
        False
        []
        ["Generated by apiary-purescript. purescript version: " ++ VERSION_purescript]
        P.defaultCompileOptions
        { P.optionsMain  = Just "Main" }

data PureScript = PureScript
    { pscConfig :: PureScriptConfig
    , compiled  :: IORef (H.HashMap FilePath String)
    }
instance Extension PureScript

makePureScript :: PureScriptConfig -> IO PureScript
makePureScript conf = do
    ir <- mapM (\p -> (p,) <$> compile conf p) (initialCompiles conf)
    p  <- PureScript conf <$> newIORef (H.fromList ir)
    return p

compile :: PureScriptConfig -> FilePath -> IO String
compile opt p = do
    mods <- G.globDir (libraryPatterns opt) (libraryBaseDir opt)
        >>= mapM (\f -> (f,) <$> readFile f) . (p:) . concat . fst
    case P.parseModulesFromFiles id $ ("prelude", P.prelude) : mods of
        Left l   -> throwIO (ParseError l)
        Right ms -> case runReaderT (P.compile (map snd ms) (pureScriptPrefix opt)) (pureScriptOptions opt) of
            Left l         -> throwIO (CompileError l)
            Right (js,_,_) -> return js

pureScript :: MonadIO m => PureScript -> FilePath -> ActionT exts prms m ()
pureScript env p = do
    contentType "text/javascript"
    s <- liftIO . try $ 
        if development (pscConfig env)
        then compile (pscConfig env) p
        else (H.lookup p <$> readIORef (compiled env)) >>= \case
           Nothing -> do
               r <- compile (pscConfig env) p
               atomicModifyIORef' (compiled env) ((,()) . H.insert p r)
               return r
           Just r  -> return r
    case s of
        Right r -> string r
        Left  e | development (pscConfig env) -> do
            bytes "console.error(\""
            appendString $ pr (e :: PureScriptException)
            appendBytes "\")"
                | otherwise -> bytes "console.error(\"PureScript error.\");"
  where
    pr = concatMap esc . show
    esc '"'  = "\\\""
    esc '\'' = "\\'"
    esc '\\' = "\\\\"
    esc '/'  = "\\/"
    esc '<'  = "\\x3c"
    esc '>'  = "\\x3e"
    esc '\n' = "\\n"
    esc c    = [c]
