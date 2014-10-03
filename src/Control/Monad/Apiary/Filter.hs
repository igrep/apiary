{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}

module Control.Monad.Apiary.Filter (
    -- * http method
      method
    -- * http version
    , http09, http10, http11
    -- * path matcher
    , root
    , capture
    -- * query matcher
    , (??)
    , (=:), (=!:), (=?:), (=?!:), (=*:), (=+:)
    , switchQuery

    -- * header matcher
    , eqHeader
    , header
    , accept

    -- * other
    , ssl

    -- * not export from Web.Apiary
    , HasDesc(..)
    , QueryKey(..)
    , query
    , Control.Monad.Apiary.Filter.httpVersion
    , Capture.path
    , Capture.endPath
    , Capture.fetch
    , Capture.restPath
    , Capture.anyPath

    , function, function', function_, focus
    , Doc(..)
    
    ) where

import Network.Wai as Wai
import Network.Wai.Parse (parseContentType)
import qualified Network.HTTP.Types as Http

import Control.Applicative
import Control.Monad
import Control.Monad.Trans

import Control.Monad.Apiary.Action.Internal
import Control.Monad.Apiary.Filter.Internal
import Control.Monad.Apiary.Filter.Internal.Capture.TH
import Control.Monad.Apiary.Internal
import qualified Control.Monad.Apiary.Filter.Internal.Capture as Capture

import Text.Blaze.Html
import qualified Data.ByteString.Char8 as SC
import qualified Data.Text          as T
import qualified Data.Text.Encoding as T
import qualified Data.CaseInsensitive as CI
import Data.Monoid
import Data.Proxy
import Data.Apiary.Compat
import Data.Apiary.Dict

import Data.Apiary.Param
import Data.Apiary.Method

-- | filter by HTTP method. since 0.1.0.0.
--
-- @
-- method GET      -- stdmethod
-- method \"HOGE\" -- non standard method
-- @
method :: Monad actM => Method -> ApiaryT exts prms actM m () -> ApiaryT exts prms actM m ()
method m = focus' (DocMethod m) (Just m) id getParams

-- | filter by ssl accessed. since 0.1.0.0.
ssl :: Monad actM => ApiaryT exts prms actM m () -> ApiaryT exts prms actM m ()
ssl = function_ (DocPrecondition "SSL required") isSecure

-- | http version filter. since 0.5.0.0.
httpVersion :: Monad actM => Http.HttpVersion -> Html -> ApiaryT exts prms actM m () -> ApiaryT exts prms actM m ()
httpVersion v h = function_ (DocPrecondition h) $ (v ==) . Wai.httpVersion

-- | http/0.9 only accepted fiter. since 0.5.0.0.
http09 :: Monad actM => ApiaryT exts prms actM m () -> ApiaryT exts prms actM m ()
http09 = Control.Monad.Apiary.Filter.httpVersion Http.http09 "HTTP/0.9 only"

-- | http/1.0 only accepted fiter. since 0.5.0.0.
http10 :: Monad actM => ApiaryT exts prms actM m () -> ApiaryT exts prms actM m ()
http10 = Control.Monad.Apiary.Filter.httpVersion Http.http10 "HTTP/1.0 only"

-- | http/1.1 only accepted fiter. since 0.5.0.0.
http11 :: Monad actM => ApiaryT exts prms actM m () -> ApiaryT exts prms actM m ()
http11 = Control.Monad.Apiary.Filter.httpVersion Http.http11 "HTTP/1.1 only"

-- | filter by 'Control.Monad.Apiary.Action.rootPattern' of 'Control.Monad.Apiary.Action.ApiaryConfig'.
root :: (Monad m, Monad actM) => ApiaryT exts prms actM m () -> ApiaryT exts prms actM m ()
root = focus' DocRoot Nothing (RootPath:) getParams

--------------------------------------------------------------------------------

newtype QueryKey (key :: Symbol) = QueryKey { queryKeyDesc :: Maybe Html }

-- | add document to query parameter filter.
--
-- > [key|key|] ?? "document" =: pInt
--
(??) :: proxy key -> Html -> QueryKey key
_ ?? d = QueryKey (Just d)

class HasDesc (a :: Symbol -> *) where
    queryDesc :: a key -> Maybe Html

instance HasDesc QueryKey where
    queryDesc = queryKeyDesc

instance HasDesc Proxy where
    queryDesc = const Nothing

instance HasDesc SProxy where
    queryDesc = const Nothing

--     type SNext w (k::Symbol) a (prms :: [(Symbol, *)]) :: [(Symbol, *)]
query :: forall query strategy k v exts prms actM m. (NotMember k prms, MonadIO actM, KnownSymbol k, ReqParam v, HasDesc query, Strategy strategy)
      => query k -> strategy v -> ApiaryT exts (SNext strategy k v prms) actM m () -> ApiaryT exts prms actM m ()
query k w = focus (DocQuery (T.pack $ symbolVal k) (strategyRep w) (reqParamRep (Proxy :: Proxy v)) (queryDesc k)) $ do
    qs      <- getQueryParams
    (ps,fs) <- getRequestBody
    let as = map snd . filter ((SC.pack (symbolVal k) ==) . fst) $ reqParams (Proxy :: Proxy v) qs ps fs
    maybe mzero return . strategy w k as =<< getParams

-- | get first matched paramerer. since 0.5.0.0.
--
-- @
-- [key|key|] =: pInt
-- @
(=:) :: (HasDesc query, MonadIO actM, ReqParam v, KnownSymbol k, NotMember k prms)
     => query k -> proxy v -> ApiaryT exts (k := v ': prms) actM m () -> ApiaryT exts prms actM m ()
k =: v = query k (pFirst v)

-- | get one matched paramerer. since 0.5.0.0.
--
-- when more one parameger given, not matched.
--
-- @
-- [key|key|] =!: pInt
-- @
(=!:) :: (HasDesc query, MonadIO actM, ReqParam v, KnownSymbol k, NotMember k prms)
      => query k -> proxy v -> ApiaryT exts (k := v ': prms) actM m () -> ApiaryT exts prms actM m ()
k =!: t = query k (pOne t)

-- | get optional first paramerer. since 0.5.0.0.
--
-- when illegal type parameter given, fail match(don't give Nothing).
--
-- @
-- [key|key|] =?: pInt
-- @
(=?:) :: (HasDesc query, MonadIO actM, ReqParam v, KnownSymbol k, NotMember k prms)
      => query k -> proxy v
      -> ApiaryT exts (k := Maybe v ': prms) actM m () -> ApiaryT exts prms actM m ()
k =?: t = query k (pOption t)

-- | get optional first paramerer with default. since 0.16.0.
--
-- when illegal type parameter given, fail match(don't give Nothing).
--
-- @
-- [key|key|] =!?: (0 :: Int)
-- @
(=?!:) :: forall query k v exts prms actM m. (HasDesc query, MonadIO actM, Show v, ReqParam v, KnownSymbol k, NotMember k prms)
       => query k -> v
       -> ApiaryT exts (k := v ': prms) actM m () -> ApiaryT exts prms actM m ()
k =?!: v = query k (pOptional v)

-- | get many paramerer. since 0.5.0.0.
--
-- @
-- [key|key|] =*: pInt
-- @
(=*:) :: (HasDesc query, MonadIO actM, ReqParam v, KnownSymbol k, NotMember k prms)
      => query k -> proxy v
      -> ApiaryT exts (k := [v] ': prms) actM m () -> ApiaryT exts prms actM m ()
k =*: t = query k (pMany t)

-- | get some paramerer. since 0.5.0.0.
--
-- @
-- [key|key|] =+: pInt
-- @
(=+:) :: (HasDesc query, MonadIO actM, ReqParam v, KnownSymbol k, NotMember k prms)
      => query k -> proxy v
      -> ApiaryT exts (k := [v] ': prms) actM m () -> ApiaryT exts prms actM m ()
k =+: t = query k (pSome t)

-- | get existance of key only query parameter. since v0.17.0.
switchQuery :: (HasDesc proxy, MonadIO actM, KnownSymbol k, NotMember k prms)
            => proxy k -> ApiaryT exts (k := Bool ': prms) actM m () -> ApiaryT exts prms actM m ()
switchQuery k = focus (DocQuery (T.pack $ symbolVal k) (StrategyRep "switch") NoValue (queryDesc k)) $ do
    qs      <- getQueryParams
    (ps,fs) <- getRequestBody
    let n = maybe False id . fmap (maybe True id) . lookup (SC.pack $ symbolVal k) $ reqParams (Proxy :: Proxy Bool) qs ps fs
    insert k n <$> getParams

--------------------------------------------------------------------------------

-- | filter by header and get first. since 0.6.0.0.
header :: (KnownSymbol k, Monad actM, NotMember k prms)
       => proxy k -> ApiaryT exts (k := SC.ByteString ': prms) actM m () -> ApiaryT exts prms actM m ()
header k = focus' (DocPrecondition $ "has header: " <> toHtml (symbolVal k)) Nothing id $ do
    n <- maybe mzero return . lookup (CI.mk . SC.pack $ symbolVal k) . requestHeaders =<< getRequest
    insert k n <$> getParams

-- | check whether to exists specified valued header or not. since 0.6.0.0.
eqHeader :: (KnownSymbol k, Monad actM)
         => proxy k -> SC.ByteString -> ApiaryT exts prms actM m () -> ApiaryT exts prms actM m ()
eqHeader k v = focus' (DocPrecondition $ "header: " <> toHtml (symbolVal k) <> " = " <> toHtml (show v)) Nothing id $ do
    v' <- maybe mzero return . lookup (CI.mk . SC.pack $ symbolVal k) . requestHeaders =<< getRequest
    if v == v' then getParams else mzero


-- | require Accept header and set response Content-Type. since 0.16.0.
accept :: Monad actM => ContentType -> ApiaryT exts prms actM m () -> ApiaryT exts prms actM m ()
accept ect = focus (DocPrecondition $ "Accept: " <> toHtml (T.decodeUtf8 ect)) $
    (lookup "Accept" . requestHeaders <$> getRequest) >>= \case
        Nothing -> mzero
        Just ac -> if parseContentType ect `elem` map (parseContentType . SC.dropWhile (== ' ')) (SC.split ',' ac)
                   then contentType ect >> getParams
                   else mzero
