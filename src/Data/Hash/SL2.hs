-- |
-- Module     : Data.Hash.SL2
-- License    : MIT
-- Maintainer : Sam Rijs <srijs@airpost.net>
--
-- An algebraic hash function, inspired by the paper /Hashing with SL2/ by
-- Tillich and Zemor.
--
-- The hash function is based on matrix multiplication in the special linear group
-- of degree 2, over a Galois field of order 2^127,  with all computations modulo
-- the polynomial x^127 + x^63 + 1.
--
-- This construction gives some nice properties, which traditional bit-scambling
-- hash functions don't possess, including it being composable. It holds:
--
-- prop> hash (m1 <> m2) == hash m1 <> hash m2
--
-- Following that, the hash function is also parallelisable. If a message can be divided
-- into a list of chunks, the hash of the message can be calculated in parallel:
--
-- > mconcat (parMap rpar hash chunks)
--
-- All operations in this package are implemented in a very efficient manner using SSE instructions.
--

module Data.Hash.SL2 (Hash, hash, (<+), (+>), (<|), (|>), parse) where

import Data.Hash.SL2.Internal (Hash)
import Data.Hash.SL2.Unsafe
import qualified Data.Hash.SL2.Mutable as Mutable

import System.IO.Unsafe

import Data.ByteString (ByteString)

import Control.Monad (mapM_)
import Data.Monoid
import Data.Functor
import Data.Foldable (Foldable)

instance Show Hash where
  show h = unsafePerformIO $ unsafeUseAsPtr h Mutable.serialize

instance Eq Hash where
  a == b = unsafePerformIO $ unsafeUseAsPtr2 a b Mutable.eq

instance Monoid Hash where
  mempty = fst $ unsafePerformIO $ unsafeWithNew Mutable.unit
  mappend a b = fst $ unsafePerformIO $ unsafeWithNew (unsafeUseAsPtr2 a b . Mutable.concat)
  mconcat [] = mempty
  mconcat [h] = h
  mconcat (h:hs) = fst $ unsafePerformIO $ Mutable.withCopy h $ \p ->
    mapM_ (flip unsafeUseAsPtr $ Mutable.concat p p) hs

-- | /O(n)/ Calculate the hash of the 'ByteString'. Alias for @('mempty' '<+')@.
hash :: ByteString -> Hash
hash = (<+) mempty

-- | /O(n)/ Append the hash of the 'ByteString' to the existing 'Hash'.
-- A significantly faster equivalent of @((. 'hash') . ('<>'))@.
infixl 7 <+
(<+) :: Hash -> ByteString -> Hash
(<+) h s = fst $ unsafePerformIO $ Mutable.withCopy h $ Mutable.append s

-- | /O(n)/ Prepend the hash of the 'ByteString' to the existing 'Hash'.
-- A significantly faster equivalent of @(('<>') . 'hash')@.
infixr 7 +>
(+>) :: ByteString -> Hash -> Hash
(+>) s h = fst $ unsafePerformIO $ Mutable.withCopy h $ Mutable.prepend s

-- | /O(n)/ Append the hash of every 'ByteString' to the existing 'Hash', from left to right.
-- A significantly faster equivalent of @('foldl' ('<+'))@.
infixl 7 <|
(<|) :: Foldable t => Hash -> t ByteString -> Hash
(<|) h ss = fst $ unsafePerformIO $ Mutable.withCopy h $ Mutable.foldAppend ss

-- | /O(n)/ Prepend the hash of every 'ByteString' to the existing 'Hash', from right to left.
-- A significantly faster equivalent of @('flip' ('foldr' ('+>')))@.
infixr 7 |>
(|>) :: Foldable t => t ByteString -> Hash -> Hash
(|>) ss h = fst $ unsafePerformIO $ Mutable.withCopy h $ Mutable.foldPrepend ss

-- | /O(1)/ Parse the representation generated by 'show'.
parse :: String -> Maybe Hash
parse s = (\(h, r) -> h <$ r) $ unsafePerformIO $ unsafeWithNew $ Mutable.unserialize s
