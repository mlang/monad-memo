{- |
Module      :  Control.Monad.Trans.Memo.Array
Copyright   :  (c) Eduard Sergeev 2013
License     :  BSD-style (see the file LICENSE)

Maintainer  :  eduard.sergeev@gmail.com
Stability   :  experimental
Portability :  non-portable (multi-param classes, flexible instances)

ArrayCache - mutable-array-based (`IO` and `ST` hosted) `MonadCache`

Very fast memoization cache. Unfortunatelly it cannot suit every case (see limitations), but if you can use it, please do: it is generally an order of magnitude faster than `Data.Map`-based `Control.Monad.Trans.Memo.Map.Memo`, especially /unboxed/ version - try to use it whenever you can.

Limitations: Since `Data.Array.Base.MArray` is used as `MonadCache` the key range must be known beforehand and the array is allocated before the first call.
It is therefore most suitable for the cases when the distribution of possible key values is within reasonable range and is rather dense (the best case: all values withing some range will be used). If this is the case then `MArray` has O(1) for both lookup and update operations.
In addition unboxed `UArrayCache` can only store unboxed types (but it does it very efficiently).

-}

{-# LANGUAGE NoImplicitPrelude,
  MultiParamTypeClasses, FunctionalDependencies,
  FlexibleInstances, FlexibleContexts,
  UndecidableInstances, TypeFamilies #-}

module Control.Monad.Memo.Array
(

   -- * ArrayCache for boxed types
   Array,
   ArrayCache,
   ArrayMemo,
   evalArrayMemo,
   runArrayMemo,
   -- * ArrayCache for unboxed types
   UArray,
   UArrayCache,
   UArrayMemo,
   evalUArrayMemo,
   runUArrayMemo,
   -- * Generic function for ArrayCache
   Container(..),
   Cache,
   genericEvalArrayMemo,
   genericRunArrayMemo

) where


import Data.Function
import Data.Maybe (Maybe(..))
import Data.Array.ST
import Data.Array.IO
import Control.Applicative
import Control.Monad
import Control.Monad.Fix
import Control.Monad.Trans
import Control.Monad.ST
import System.IO

import Data.MaybeLike
import Control.Monad.Memo.Class
import Control.Monad.Trans.Memo.ReaderCache


newtype Container c k e = Container { toArray :: c k e }

type Cache c k e = ReaderCache (Container c k e)

instance (Monad m, Ix k, MaybeLike e v, MArray c e m) =>
    MonadCache k v (Cache c k e m) where
        {-# INLINE lookup #-}
        lookup k = do
          c <- container
          e <- lift $ readArray (toArray c) k
          return (if isNothing e then Nothing else Just (fromJust e))
        {-# INLINE add #-}
        add k v = do 
          c <- container
          lift $ writeArray (toArray c) k (just v) 

instance (Monad m, Ix k, MaybeLike e v, MArray c e m) =>
    MonadMemo k v (Cache c k e m) where
        {-# INLINE memo #-}
        memo f k = do
          c <- container
          e <- lift $ readArray (toArray c) k
          if isNothing e
            then do
              v <- f k
              lift $ writeArray (toArray c) k (just v)
              return v
            else return (fromJust e) 


-- ArrayCache for boxed types
-- --------------------------

-- | A family of boxed arrays
type family Array (m :: * -> *) :: * -> * -> *

type instance Array (ST s) = STArray s
type instance Array IO = IOArray

-- | Memoization monad based on mutable boxed array
type ArrayCache k e m = Cache (Array m) k e m

-- | This is just to be able to infer the type of the `ArrayCache` element.
-- Type families could be used instead but due to the bug in 7.4.* we cannot use them here
class MaybeLike e v => ArrayMemo v e | v -> e

-- | Given the key-range, compute the result of a memoized computation using boxed array.
-- This function discards the final state of the cache
evalArrayMemo :: (Ix k, MArray (Array m) e m, ArrayMemo v e) =>
                 ArrayCache k e m a -> (k,k) -> m a
{-# INLINE evalArrayMemo #-}
evalArrayMemo = genericEvalArrayMemo

-- | Given the key-range, compute the result of a memoized computation using boxed array.
-- This function also returns the final content of the array cache
runArrayMemo :: (Ix k, MArray (Array m) e m, ArrayMemo v e) =>
                ArrayCache k e m a -> (k,k) -> m (a, Array m k e)
{-# INLINE runArrayMemo #-}
runArrayMemo = genericRunArrayMemo


-- ArrayCache for unboxed types
-- ----------------------------

-- | A family of unboxed arrays
type family UArray (m :: * -> *) :: * -> * -> *

type instance UArray (ST s) = STUArray s
type instance UArray IO = IOUArray

-- | Memoization monad based on mutable unboxed array
type UArrayCache k e m = Cache (UArray m) k e m

-- | This is just to be able to infer the type of the `UArrayCache` element.
-- Type families could be used instead but due to the bug in 7.4.* we cannot use them here
class MaybeLike e v => UArrayMemo v e | v -> e

-- | Given the key-range, compute the result of a memoized computation using unboxed array.
-- This function discards the final state of the cache
evalUArrayMemo :: (Ix k, MArray (UArray m) e m, UArrayMemo v e) =>
                  UArrayCache k e m a -> (k,k) -> m a
{-# INLINE evalUArrayMemo #-}
evalUArrayMemo = genericEvalArrayMemo

-- | Given the key-range, compute the result of a memoized computation using boxed array.
-- This function also returns the final content of the array cache
runUArrayMemo :: (Ix k, MArray (UArray m) e m, UArrayMemo v e) =>
                 UArrayCache k e m a -> (k,k) -> m (a, UArray m k e)
{-# INLINE runUArrayMemo #-}
runUArrayMemo = genericRunArrayMemo

genericEvalArrayMemo :: (Ix k, MaybeLike e v, MArray arr e m) =>
                        Cache arr k e m a -> (k, k) -> m a
{-# INLINE genericEvalArrayMemo #-}
genericEvalArrayMemo m lu = do
  arr <- newArray lu nothing
  evalReaderCache m (Container arr)

genericRunArrayMemo :: (Ix k, MaybeLike e v, MArray arr e m) =>
                       Cache arr k e m a -> (k, k) -> m (a, arr k e)
{-# INLINE genericRunArrayMemo #-}
genericRunArrayMemo m lu = do
  arr <- newArray lu nothing
  a <- evalReaderCache m (Container arr)
  return (a, arr)
