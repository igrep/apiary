{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Data.Apiary.Extension
    ( Has(getExtension)
    , MonadExts(..), getExt
    , Extension(..)
    , Extensions
    , noExtension
    -- * initializer constructor
    , Initializer,  initializer
    , Initializer', initializer'
    , initializerBracket
    , initializerBracket'

    -- * combine initializer
    , (+>)
    ) where

import Control.Monad.Reader
import Data.Apiary.Extension.Internal

class Monad m => MonadExts es m | m -> es where
    getExts :: m (Extensions es)

getExt :: (MonadExts es m, Has e es) => proxy e -> m e
getExt p = getExtension p `liftM` getExts

instance Monad m => MonadExts es (ReaderT (Extensions es) m) where
    getExts = ask

type Initializer' m a = forall i. Initializer m i (a ': i)

addExtension :: Extension e => e -> Extensions es -> Extensions (e ': es)
addExtension = AddExtension

initializer :: (Extension e, Monad m) => (Extensions es -> m e) -> Initializer m es (e ': es)
initializer m = Initializer $ \es n -> do
    e <- m es
    n (addExtension e es)

initializer' :: (Extension e, Monad m) => m e -> Initializer' m e
initializer' m = initializer (const m)

initializerBracket :: Extension e => (forall a. Extensions es -> (e -> m a) -> m a) -> Initializer m es (e ': es)
initializerBracket b = Initializer $ \es n ->
    b es $ \e -> n (addExtension e es)

initializerBracket' :: Extension e => (forall a. (e -> m a) -> m a) -> Initializer m es (e ': es)
initializerBracket' m = initializerBracket (const m)

-- | combine two Initializer. since 0.16.0.
(+>) :: Monad m => Initializer m i x -> Initializer m x o -> Initializer m i o
Initializer a +> Initializer b = Initializer $ \e m -> a e (\e' -> b e' m)

noExtension :: Monad m => Initializer m i i
noExtension = Initializer $ \es n -> n es
