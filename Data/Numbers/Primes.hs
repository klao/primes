-- |
-- Module      : Data.Numbers.Primes
-- Copyright   : Sebastian Fischer
-- License     : PublicDomain
-- 
-- Maintainer  : Sebastian Fischer (sebf@informatik.uni-kiel.de)
-- Stability   : experimental
-- Portability : portable
-- 
-- This Haskell library provides an efficient lazy wheel sieve for
-- prime generation inspired by /Lazy wheel sieves and spirals of/
-- /primes/ by Colin Runciman
-- (<http://www.cs.york.ac.uk/ftpdir/pub/colin/jfp97lw.ps.gz>) and
-- /The Genuine Sieve of Eratosthenes/ by Melissa O'Neil
-- (<http://www.cs.hmc.edu/~oneill/papers/Sieve-JFP.pdf>).
-- 
module Data.Numbers.Primes ( primes, wheelSieve ) where

-- | 
-- This global constant is an infinite list of prime numbers. It is
-- generated by a lazy wheel sieve and shared across the whoe program
-- run. If you are concerned about the memory requirements of sharing
-- many primes you can call the function @wheelSieve@ directly.
-- 
primes :: [Integer]
primes = wheelSieve 6

-- | 
-- This function returns an infinite list of prime numbers by sieving
-- with a wheel that cancels the multiples of the first @n@ primes
-- where @n@ is the argument given to @wheelSieve@. Don't use too large
-- wheels. The number @6@ is a good value to pass to this
-- function. Larger wheels improve the run time at the cost of higher
-- memory requirements.
-- 
wheelSieve :: Int        -- ^ number of primes canceled by the wheel
           -> [Integer]  -- ^ infinite list of primes
wheelSieve k = reverse ps ++ toList (fmap first (sieve p (cyclic ns)))
 where (p:ps,ns) = wheel k

-- Auxiliary Definitions
------------------------------------------------------------------------------

-- We use a datatype for infinite lists with unboxed elements to
-- compute primes.
-- 
data List a = List !a (List a)

instance Functor List where
  fmap f (List x xs) = List (f x) (fmap f xs)

first :: List a -> a
first (List x _) = x

toList :: List a -> [a]
toList (List x xs) = x : toList xs

cyclic :: [a] -> List a
cyclic xs = s where s = prepend xs s

prepend :: [a] -> List a -> List a
prepend []     s = s
prepend (x:xs) s = List x (prepend xs s)

-- Sieves prime candidates by computing composites from the result of
-- a recursive call with identical arguments. We could use sharing
-- instead of a recursive call with identical arguments but that would
-- lead to moch higher memory requirements. The results of the
-- different calls are consumed at different speeds and we want to
-- avoid multiple far apart pointers into the result list to avoid
-- retaining everything in between.
--
-- Each list in the result starts with a prime. To obtain composites
-- that need to be cancelled, one can multiply all elements of the
-- list with its head.
-- 
sieve :: Integer -> List Integer -> List (List Integer)
sieve p ns@(List m ms) =
  List (spin p ns)
         (sieveComps (p+m) ms
           (Empty, fmap comps (List (spin p ns) (sieve p ns))))
 where comps xs@(List x _) = fmap (x*) xs

-- Composites are stored in increasing order in a priority queue. The
-- queue has an associated feeder which is used to avoid filling it
-- with entries that will only be used again much later. The feeder is
-- computed from the result of a call to 'sieve'.
-- 
type Composites = (Queue, List (List Integer))

-- We can split all composites into the next and remaining
-- composites. We use the feeder when appropriate and discard equal
-- entries to not return a composite twice.
-- 
splitComposites :: Composites -> (Integer, Composites)
splitComposites (Empty, List xs xss) = splitComposites (Fork xs [], xss)
splitComposites (queue, xss@(List (List x xs) yss))
  | x < z     = (x, discard x (enqueue xs queue, yss))
  | otherwise = (z, discard z (enqueue zs queue', xss))
 where (List z zs,queue') = dequeue queue

-- Drops all occurrences of the given element.
--
discard :: Integer -> Composites -> Composites
discard n ns | n == m    = discard n ms
             | otherwise = ns
 where (m,ms) = splitComposites ns

-- This is the actual sieve. It discards candidates that are
-- composites and yields lists which start with a prime and contain
-- all factors of the composites that need to be dropped.
--
sieveComps :: Integer -> List Integer -> Composites -> List (List Integer)
sieveComps cand ns@(List m ms) xs
  | cand == comp = sieveComps (cand+m) ms ys
  | cand <  comp = List (spin cand ns) (sieveComps (cand+m) ms xs)
  | otherwise    = sieveComps cand ns ys
 where (comp,ys) = splitComposites xs

-- This function computes factors of composites of primes by spinning
-- a wheel.
-- 
spin :: Integer -> List Integer -> List Integer
spin x (List y ys) = List x (spin (x+y) ys)

-- A wheel consists of a list of primes whose multiples are canceled
-- and the actual wheel that is rolled for canceling.
--
type Wheel = ([Integer],[Integer])

-- Computes a wheel that cancels the multiples of the given number
-- (plus 1) of primes.
--
-- For example:
--
-- wheel 0 = ([2],[1])
-- wheel 1 = ([3,2],[2])
-- wheel 2 = ([5,3,2],[2,4])
-- wheel 3 = ([7,5,3,2],[4,2,4,2,4,6,2,6])
--
wheel :: Int -> Wheel
wheel n = iterate next ([2],[1]) !! n

next :: Wheel -> Wheel
next (ps@(p:_),xs) = (py:ps,cancel (product ps) p py ys)
 where (y:ys) = cycle xs
       py = p + y

cancel :: Integer -> Integer -> Integer -> [Integer] -> [Integer]
cancel 0 _ _ _ = []
cancel m p n (x:ys@(y:zs))
  | nx `mod` p > 0 = x : cancel (m-x) p nx ys
  | otherwise      = cancel m p n (x+y:zs)
 where nx = n + x

-- We use a special version of priority queues implemented as /pairing/
-- /heaps/ (see /Purely Functional Data Structures/ by Chris Okasaki).
--
-- The queue stores non-empty lists of composites; the first element
-- is used as priority.
--
data Queue = Empty | Fork (List Integer) [Queue]

enqueue :: List Integer -> Queue -> Queue
enqueue ns = merge (Fork ns [])

merge :: Queue -> Queue -> Queue
merge Empty y                        = y
merge x     Empty                    = x
merge x     y     | prio x <= prio y = join x y
                  | otherwise        = join y x
 where prio (Fork (List n _) _) = n
       join (Fork ns qs) q      = Fork ns (q:qs)

dequeue :: Queue -> (List Integer, Queue)
dequeue (Fork ns qs) = (ns,mergeAll qs)

mergeAll :: [Queue] -> Queue
mergeAll []       = Empty
mergeAll [x]      = x
mergeAll (x:y:qs) = merge (merge x y) (mergeAll qs)
