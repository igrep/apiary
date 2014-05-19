{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Control.Monad.Apiary.Filter (
    -- * filters
    -- ** http method
      method, stdMethod
    -- ** http version
    , Control.Monad.Apiary.Filter.httpVersion
    , http09, http10, http11
    -- ** path matcher
    , root
    , capture

    -- ** query matcher
    , query
    -- *** specified operators
    , (=:), (=!:), (=?:), (?:), (=*:), (=+:)
    , hasQuery

    -- ** header matcher
    , hasHeader
    , eqHeader
    , headers
    , header
    , header'

    -- ** other
    , ssl
    
    -- * Reexport
    -- | StdMethod(..)
    , module Network.HTTP.Types
    -- | Strategy Proxies
    , module Control.Monad.Apiary.Filter.Internal.Strategy

    ) where

import Control.Monad
import Network.Wai as Wai
import qualified Network.HTTP.Types as HT
import Network.HTTP.Types (StdMethod(..))
import qualified Data.ByteString as S
import Data.Proxy
import Data.Reflection

import Data.Apiary.SList
import Data.Apiary.Param

import Control.Monad.Apiary.Action.Internal
import Control.Monad.Apiary.Filter.Internal
import qualified Control.Monad.Apiary.Filter.Internal.Strategy as Strategy
import Control.Monad.Apiary.Filter.Internal.Strategy (pFirst, pOne, pOption, pCheck, pMany, pSome)
import Control.Monad.Apiary.Filter.Internal.Capture.TH
import Control.Monad.Apiary.Internal

-- | filter by HTTP method. since 0.1.0.0.
method :: Monad m => HT.Method -> ApiaryT c m a -> ApiaryT c m a
method m = function_ ((m ==) . requestMethod)

-- | filter by HTTP method using StdMethod. since 0.1.0.0.
stdMethod :: Monad m => StdMethod -> ApiaryT c m a -> ApiaryT c m a
stdMethod = method . HT.renderStdMethod

-- | filter by ssl accessed. since 0.1.0.0.
ssl :: Monad m => ApiaryT c m a -> ApiaryT c m a
ssl = function_ isSecure

-- | http version filter. since 0.5.0.0.
httpVersion :: Monad m => HT.HttpVersion  -> ApiaryT c m b -> ApiaryT c m b
httpVersion v = function_ $ (v ==) . Wai.httpVersion

-- | http/0.9 only accepted fiter. since 0.5.0.0.
http09 :: Monad m => ApiaryT c m b -> ApiaryT c m b
http09 = Control.Monad.Apiary.Filter.httpVersion HT.http09

-- | http/1.0 only accepted fiter. since 0.5.0.0.
http10 :: Monad m => ApiaryT c m b -> ApiaryT c m b
http10 = Control.Monad.Apiary.Filter.httpVersion HT.http10

-- | http/1.1 only accepted fiter. since 0.5.0.0.
http11 :: Monad m => ApiaryT c m b -> ApiaryT c m b
http11 = Control.Monad.Apiary.Filter.httpVersion HT.http11

-- | filter by 'Control.Monad.Apiary.Action.rootPattern' of 'Control.Monad.Apiary.Action.ApiaryConfig'.
root :: Monad m => ApiaryT c m b -> ApiaryT c m b
root m = do
    rs <- rootPattern `liftM` apiaryConfig
    function_ (\r -> rawPathInfo r `elem` rs) m

-- | low level query getter. since 0.5.0.0.
--
-- @
-- query "key" (Proxy :: Proxy (fetcher type))
-- @
--
-- examples:
--
-- @
-- query "key" (Proxy :: Proxy ('First' Int)) -- get first \'key\' query parameter as Int.
-- query "key" (Proxy :: Proxy ('Option' (Maybe Int)) -- get first \'key\' query parameter as Int. allow without param or value.
-- query "key" (Proxy :: Proxy ('Many' String) -- get all \'key\' query parameter as String.
-- @
-- 
query :: (Query a, Strategy.Strategy w, Monad m)
      => S.ByteString
      -> Proxy (w a)
      -> ApiaryT (Strategy.SNext w as a) m b
      -> ApiaryT as m b
query k p = function $ \l r -> Strategy.readStrategy readQuery ((k ==) . fst) p (queryString r) l

-- | get first matched paramerer. since 0.5.0.0.
--
-- @
-- "key" =: pInt == query "key" (pFirst pInt) == query "key" (Proxy :: Proxy (First Int))
-- @
(=:) :: (Query a, Monad m)
     => S.ByteString -> Proxy a -> ApiaryT (Snoc as a) m b -> ApiaryT as m b
k =: t = query k (pFirst t)

-- | get one matched paramerer. since 0.5.0.0.
--
-- when more one parameger given, not matched.
--
-- @
-- "key" =: pInt == query "key" (pOne pInt) == query "key" (Proxy :: Proxy (One Int))
-- @
(=!:) :: (Query a, Monad m)
      => S.ByteString -> Proxy a -> ApiaryT (Snoc as a) m b -> ApiaryT as m b
k =!: t = query k (pOne t)

-- | get optional first paramerer. since 0.5.0.0.
--
-- when illegal type parameter given, fail mather(don't give Nothing).
--
-- @
-- "key" =: pInt == query "key" (pOption pInt) == query "key" (Proxy :: Proxy (Option Int))
-- @
(=?:) :: (Query a, Monad m)
      => S.ByteString -> Proxy a -> ApiaryT (Snoc as (Maybe a)) m b -> ApiaryT as m b
k =?: t = query k (pOption t)

-- | check parameger given and type. since 0.5.0.0.
--
-- If you wan't to allow any type, give 'pVoid'.
--
-- @
-- "key" =: pInt == query "key" (pCheck pInt) == query "key" (Proxy :: Proxy (Check Int))
-- @
(?:) :: (Query a, Monad m)
     => S.ByteString -> Proxy a -> ApiaryT as m b -> ApiaryT as m b
k ?: t = query k (pCheck t)

-- | get many paramerer. since 0.5.0.0.
--
-- @
-- "key" =: pInt == query "key" (pMany pInt) == query "key" (Proxy :: Proxy (Many Int))
-- @
(=*:) :: (Query a, Monad m)
      => S.ByteString -> Proxy a -> ApiaryT (Snoc as [a]) m b -> ApiaryT as m b
k =*: t = query k (pMany t)

-- | get some paramerer. since 0.5.0.0.
--
-- @
-- "key" =: pInt == query "key" (pSome pInt) == query "key" (Proxy :: Proxy (Some Int))
-- @
(=+:) :: (Query a, Monad m)
      => S.ByteString -> Proxy a -> ApiaryT (Snoc as [a]) m b -> ApiaryT as m b
k =+: t = query k (pSome t)

-- | query exists checker.
--
-- @
-- hasQuery q = 'query' q (Proxy :: Proxy ('Check' ()))
-- @
--
hasQuery :: Monad m => S.ByteString -> ApiaryT c m a -> ApiaryT c m a
hasQuery q = query q (Proxy :: Proxy (Strategy.Check ()))

--------------------------------------------------------------------------------

-- | check whether to exists specified header or not. since 0.6.0.0.
hasHeader :: Monad m => HT.HeaderName
          -> ApiaryT as m b -> ApiaryT as m b
hasHeader n = header' pCheck ((n ==) . fst)

-- | check whether to exists specified valued header or not. since 0.6.0.0.
eqHeader :: Monad m => HT.HeaderName 
         -> S.ByteString  -- ^ header value
         -> ApiaryT as m b
         -> ApiaryT as m b
eqHeader k v = header' pCheck (\(k',v') -> k == k' && v == v')

-- | filter by header and get first. since 0.6.0.0.
header :: Monad m => HT.HeaderName
       -> ApiaryT (Snoc as S.ByteString) m b -> ApiaryT as m b
header n = header' pFirst ((n ==) . fst)

-- | filter by headers up to 100 entries. since 0.6.0.0.
headers :: Monad m => HT.HeaderName
        -> ApiaryT (Snoc as [S.ByteString]) m b -> ApiaryT as m b
headers n = header' limit100 ((n ==) . fst)
  where
    limit100 :: Proxy x -> Proxy (Strategy.LimitSome $(int 100) x)
    limit100 _ = Proxy

-- | low level header filter. since 0.6.0.0.
header' :: (Strategy.Strategy w, Monad m)
        => (forall x. Proxy x -> Proxy (w x))
        -> (HT.Header -> Bool)
        -> ApiaryT (Strategy.SNext w as S.ByteString) m b
        -> ApiaryT as m b
header' pf kf = function $ \l r ->
    Strategy.readStrategy Just kf (pf pByteString) (requestHeaders r) l

