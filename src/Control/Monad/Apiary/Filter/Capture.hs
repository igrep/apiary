{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE DataKinds #-}

module Control.Monad.Apiary.Filter.Capture
    ( path, fetch, fetch', anyPath, restPath
    ) where

import Control.Monad.Apiary.Internal (ApiaryT, focus)
import Control.Monad.Apiary.Filter.Internal
    (Doc(DocPath, DocFetch, DocAny, DocRest))

import Data.Apiary.Compat(KnownSymbol, symbolVal, Proxy(..))
import Data.Apiary.Param(Path, pathRep, readPathAs)
import Data.Apiary.Dict(KV((:=)))
import qualified Data.Apiary.Dict as Dict
import qualified Data.Apiary.Router as R

import qualified Data.Text as T
import Text.Blaze.Html(Html)

-- | check first path and drill down. since 0.11.0.
path :: Monad actM => T.Text -> ApiaryT exts prms actM m () -> ApiaryT exts prms actM m ()
path p = focus (DocPath p) Nothing (R.exact p)

-- | get first path and drill down. since 0.11.0.
fetch' :: (k Dict.</ prms, KnownSymbol k, Path p, Monad actM) => proxy k -> proxy' p -> Maybe Html
       -> ApiaryT exts (k := p ': prms) actM m () -> ApiaryT exts prms actM m ()
fetch' k p h = focus (DocFetch (T.pack $ symbolVal k) (pathRep p) h) Nothing $ R.fetch k (readPathAs p)

fetch :: forall proxy k p exts prms actM m. (k Dict.</ prms, KnownSymbol k, Path p, Monad actM)
      => proxy (k := p) -> Maybe Html
      -> ApiaryT exts (k := p ': prms) actM m () -> ApiaryT exts prms actM m ()
fetch _ h = fetch' k p h
  where
    k = Proxy :: Proxy k
    p = Proxy :: Proxy p

anyPath :: (Monad m, Monad actM) => ApiaryT exts prms actM m () -> ApiaryT exts prms actM m ()
anyPath = focus DocAny Nothing R.any

restPath :: (k Dict.</ prms, KnownSymbol k, Monad m, Monad actM)
         => proxy k -> Maybe Html -> ApiaryT exts (k := [T.Text] ': prms) actM m () -> ApiaryT exts prms actM m ()
restPath k h = focus (DocRest (T.pack $ symbolVal k) h) Nothing (R.rest k)
