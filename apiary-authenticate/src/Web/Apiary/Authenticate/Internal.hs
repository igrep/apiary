{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}

module Web.Apiary.Authenticate.Internal where

import Control.Applicative
import Control.Monad.Trans.Resource
import Control.Monad.Apiary.Filter
import Control.Monad.Apiary.Action

import qualified Network.HTTP.Types as HTTP
import qualified Network.HTTP.Client as Client

import Web.Authenticate.OpenId
import Web.Apiary
import Web.Apiary.Session
import qualified Web.Apiary.Wai as Wai

import Data.Serialize as Serialize
import Data.Apiary.Extension
import Data.Data (Data)
import Data.Maybe
import Data.List
import Data.Apiary.Compat
import Data.Default.Class

import Blaze.ByteString.Builder
import qualified Data.ByteString.Char8 as S
import qualified Data.Text as T
import qualified Data.Text.Encoding as T


data AuthConfig = AuthConfig
    { authSuccessPage   :: S.ByteString
    , authUrl           :: T.Text

    , authPrefix        :: [T.Text]
    , authReturnToPath  :: [T.Text]
    , authLogoutPath    :: [T.Text]

    , providers         :: [(T.Text, Provider)]
    }

data Provider = Provider
    { providerUrl  :: T.Text
    , realm        :: Maybe T.Text
    , parameters   :: [(T.Text, T.Text)]
    }

instance Default AuthConfig where
    def = AuthConfig "/" "http://localhost:3000" ["auth"] ["return_to"] ["logout"] $ 
        [ ("google", Provider "https://www.google.com/accounts/o8/id" Nothing [])
        , ("yahoo",  Provider "http://me.yahoo.com/"                  Nothing [])
        ]

data Auth = Auth
    { manager           :: Client.Manager
    , config            :: AuthConfig
    }
instance Extension Auth

authHandler :: (Monad m, MonadIO actM, Has (Session OpenId actM) exts)
            => Auth -> ApiaryT exts prms actM m ()
authHandler Auth{..} = retH >> mapM_ (uncurry go) (providers config)
  where
    pfxPath p = function id (\d r -> if p `isPrefixOf` Wai.pathInfo r then Just d else Nothing)

    retH = pfxPath (authPrefix config ++ authReturnToPath config) . method GET . action $
        returnAction manager (authSuccessPage config)

    go name Provider{..} = pfxPath (authPrefix config ++ [name]) . method GET . action $
        authAction manager providerUrl returnTo realm parameters

    returnTo = T.decodeUtf8 $ T.encodeUtf8 (authUrl config) `S.append`
        toByteString (HTTP.encodePathSegments (authPrefix config ++ authReturnToPath config))

authConfig :: Auth -> AuthConfig
authConfig = config

authProviders :: Auth -> [(T.Text, Provider)]
authProviders = providers . config

authRoutes :: Auth -> [(T.Text, S.ByteString)]
authRoutes auth =
    map (\(k,_) -> (k, toByteString . HTTP.encodePathSegments $ authPrefix (config auth) ++ [k])) $
    providers (config auth)

-- | delete session. since 0.7.0.0.
authLogout :: (Has (Session OpenId m) exts, Monad m) => ActionT exts prms m ()
authLogout = deleteSession (Proxy :: Proxy OpenId)

authAction :: MonadIO m => Client.Manager -> T.Text -> T.Text
           -> Maybe T.Text -> [(T.Text, T.Text)] -> ActionT exts prms m ()
authAction mgr uri returnTo realm prm = do
    fw <- liftIO . runResourceT $ getForwardUrl uri returnTo realm prm mgr
    redirect $ T.encodeUtf8 fw

data OpenId_ a = OpenId_
    { opLocal :: a
    , params  :: [(a, a)]
    , claimed :: Maybe a
    } deriving (Show, Read, Eq, Ord, Data, Typeable, Functor)

instance Serialize.Serialize (OpenId_ S.ByteString) where
    put (OpenId_ loc prm cld) = put loc >> put prm >> put cld
    get = OpenId_ <$> get <*> get <*> get

instance Serialize.Serialize (OpenId_ T.Text) where
    get = fmap (fmap T.decodeUtf8) Serialize.get
    put = put . fmap T.encodeUtf8

type OpenId = OpenId_ T.Text

toOpenId :: OpenIdResponse -> OpenId
toOpenId r = OpenId_ 
    (identifier $ oirOpLocal r)
    (oirParams r)
    (identifier <$> oirClaimed r)

returnAction :: (MonadIO m, Has (Session OpenId m) exts)
             => Client.Manager -> S.ByteString -> ActionT exts prms m ()
returnAction mgr to = do
    q <- Wai.queryString <$> getRequest
    r <- liftIO . runResourceT $ authenticateClaimed (mapMaybe queryElem q) mgr
    setSession Proxy (toOpenId r)
    redirect to
  where
    queryElem (_, Nothing) = Nothing
    queryElem (k, Just v)  = Just (T.decodeUtf8 k, T.decodeUtf8 v)
