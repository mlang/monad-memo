{- |
Module      :  Control.Monad.Trans.Memo.Vector
Copyright   :  (c) Eduard Sergeev 2013
License     :  BSD-style (see the file LICENSE)

Maintainer  :  eduard.sergeev@gmail.com
Stability   :  experimental
Portability :  non-portable (multi-param classes, flexible instances)

VectorCache - mutable-vector-based (`IO` and `ST` hosted) `MonadCache`

The fastest memoization cache, however it is even more limiting than "Control.Monad.Memo.Mutable.Array" due to nature of "Data.Vector.Mutable". Still if you can use this cache please do since it will give you dramatic calculation speed up in comparison to pure `Data.Map.Map`-based cache, especially when unboxed `UVectorCache` is used.

Limitations: Since `Data.Vector.Generic.Mutable.MVector` is used as `MonadCache` the key must be `Int` and the size of the cache's vector must be known beforehand with vector being allocated before the first call. In addition unboxed `UVectorCache` can only store `Data.Vector.Unboxed.Unbox` values (but it does it very efficiently).

-}

{-# LANGUAGE NoImplicitPrelude,
  MultiParamTypeClasses, FunctionalDependencies,
  FlexibleInstances, FlexibleContexts, TypeFamilies,
  UndecidableInstances, GeneralizedNewtypeDeriving #-}

module Control.Monad.Memo.Vector
 (

   -- * VectorCache for boxed types
   Vector,
   VectorCache,
   VectorMemo,
   evalVectorMemo,
   runVectorMemo,
   -- * UVectorCache for unboxed types
   UVector,
   UVectorCache,
   UVectorMemo,
   evalUVectorMemo,
   runUVectorMemo,
   -- * Generic functions for VectorCache
   Container(..),
   Cache,
   genericEvalVectorMemo,
   genericRunVectorMemo

) where 

import Data.Int
import Data.Function
import Data.Maybe (Maybe(..))
import Data.Vector.Generic.Mutable
import qualified Data.Vector.Mutable as M
import qualified Data.Vector.Unboxed.Mutable as UM
import Control.Applicative
import Control.Monad
import Control.Monad.Fix
import Control.Monad.Trans
import Control.Monad.Primitive

import Data.MaybeLike
import Control.Monad.Memo.Class
import Control.Monad.Trans.Memo.ReaderCache


newtype Container c s e = Container { toVector :: c s e }

type Cache c s e = ReaderCache (Container c s e)

instance (PrimMonad m, PrimState m ~ s, MaybeLike e v, MVector c e) =>
    MonadCache Int v (Cache c s e m) where
        {-# INLINE lookup #-}
        lookup k = do
          c <- container
          e <- lift $ read (toVector c) k
          return (if isNothing e then Nothing else Just (fromJust e))
        {-# INLINE add #-}
        add k v = do 
          c <- container
          lift $ write (toVector c) k (just v)

instance (PrimMonad m, PrimState m ~ s, MaybeLike e v, MVector c e) =>
    MonadMemo Int v (Cache c s e m) where
        {-# INLINE memo #-}
        memo f k = do
          c <- container
          e <- lift $ read (toVector c) k
          if isNothing e
            then do
              v <- f k
              lift $ write (toVector c) k (just v)
              return v
            else return (fromJust e) 


-- VectorCache for boxed types
-- --------------------------

-- | Boxed vector
type Vector = M.MVector

-- | `MonadCache` based on boxed vector
type VectorCache s e = Cache Vector s e

-- | This is just to be able to infer the type of the `VectorCache` element.
class MaybeLike e v => VectorMemo v e | v -> e

-- | Evaluates `MonadMemo` computation using boxed vector
evalVectorMemo :: (PrimMonad m, VectorMemo v e) =>
                  VectorCache (PrimState m) e m a -> Int -> m a
{-# INLINE evalVectorMemo #-}
evalVectorMemo = genericEvalVectorMemo

-- | Evaluates `MonadMemo` computation using boxed vector.
-- It also returns the final content of the vector cache
runVectorMemo :: (PrimMonad m, VectorMemo v e) =>
                 VectorCache (PrimState m) e m a -> Int -> m (a, Vector (PrimState m) e)
{-# INLINE runVectorMemo #-}
runVectorMemo = genericRunVectorMemo


-- VectorCache for unboxed types
-- ----------------------------

-- | Unboxed vector
type UVector = UM.MVector

-- | `MonadCache` based on unboxed vector
type UVectorCache s e = Cache UVector s e

-- | This is just to be able to infer the type of the `UVectorCache` element.
class MaybeLike e v => UVectorMemo v e | v -> e

-- | Evaluates `MonadMemo` computation using unboxed vector
evalUVectorMemo :: (PrimMonad m, MVector UVector e, UVectorMemo v e) =>
                   UVectorCache (PrimState m) e m a -> Int -> m a                             
{-# INLINE evalUVectorMemo #-}
evalUVectorMemo = genericEvalVectorMemo

-- | Evaluates `MonadMemo` computation using unboxed vector.
-- It also returns the final content of the vector cache
runUVectorMemo :: (PrimMonad m, MVector UVector e, UVectorMemo v e) =>
                  UVectorCache (PrimState m) e m a -> Int -> m (a, UVector (PrimState m) e)
{-# INLINE runUVectorMemo #-}
runUVectorMemo = genericRunVectorMemo


--genericEvalVectorMemo :: (MaybeLike e v, PrimMonad m, MVector c e) =>
--                         Cache c (PrimState m) e m a -> Int -> m a
{-# INLINE genericEvalVectorMemo #-}
genericEvalVectorMemo m n = do
  c <- replicate n nothing
  evalReaderCache m (Container c)

--genericRunVectorMemo :: (MaybeLike e v, PrimMonad m, MVector c e) =>
--                        Cache c (PrimState m) e m a -> Int -> m (a, c (PrimState m) e)
{-# INLINE genericRunVectorMemo #-}
genericRunVectorMemo m n = do
  c <- replicate n nothing
  a <- evalReaderCache m (Container c)
  return (a, c)