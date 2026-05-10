-- Polyformalism Constraint Kernel — Haskell
-- ============================================
-- Haskell reveals: lazy evaluation means we get short-circuit constraint checking
-- for free (zipWith stops when 'and' finds False). But for Bloom filters, we need
-- strict evaluation (seq/evaluate) or the whole filter stays as a thunk.
-- The tension between lazy and strict IS the language's character.

module Main where

import Data.Bits (Bits(..))
import Data.Int (Int32, Int64)
import Data.Word (Word64)
import qualified Data.Vector.Unboxed as V

-- 1. Constraint check: vectorized bounds test
constraintCheck :: [Int32] -> [Int32] -> [Int32] -> Bool
constraintCheck lower upper values = and $ zipWith3 check lower upper values
  where
    check lo hi v = v >= lo && v <= hi

-- 2. Bloom merge: bitwise OR (CRDT semilattice join)
-- Idempotent: dst .| dst == dst
-- Commutative: dst .| src == src .| dst
-- Associative: (a .| b) .| c == a .| (b .| c)
bloomMerge :: V.Vector Word64 -> V.Vector Word64 -> V.Vector Word64
bloomMerge = V.zipWith (.|.)

-- 3. Eisenstein norm: a² - ab + b²
eisensteinNorm :: Int32 -> Int32 -> Int64
eisensteinNorm a b = fromIntegral a * fromIntegral a
                   - fromIntegral a * fromIntegral b
                   + fromIntegral b * fromIntegral b

-- Bloom helpers
bloomHash :: Int -> Int -> Int
bloomHash key totalBits = fromIntegral (h .&. maxBound) `mod` totalBits
  where
    k = fromIntegral key :: Integer
    h = k * 0x45d9f3b + 0x9e3779b97f4a7c15  -- FNV-inspired

bloomInsert :: V.Vector Word64 -> Int -> V.Vector Word64
bloomInsert filter key = V.modify (\v -> do
    let totalBits = V.length filter * 64
    let pos = abs (key * 2654435761) `mod` totalBits
    let word = pos `quot` 64
    let bit  = pos `mod` 64
    V.unsafeWrite v word (V.unsafeRead v word .|. (1 `shiftL` bit))
  ) filter

main :: IO ()
main = do
    putStrLn "=== Polyformalism: Haskell ==="

    -- Constraint check
    let lower = replicate 16 0
    let upper = replicate 16 100
    let pass  = [25, 30, 35, 40, 50, 60, 70, 80, 10, 20, 30, 40, 55, 65, 75, 85]
    let fail  = [200, 201 .. 215]

    putStrLn $ "Constraint check (pass): " ++ show (constraintCheck lower upper pass)
    putStrLn $ "Constraint check (fail): " ++ show (constraintCheck lower upper fail)

    -- Bloom merge
    let bloomA0 = V.replicate 1000 (0 :: Word64)
    let bloomB0 = V.replicate 1000 (0 :: Word64)
    -- Simple insertion: key -> bit position
    let insertKey f k = let pos = abs (k * 2654435761) `mod` (V.length f * 64)
                            word = pos `quot` 64
                            bit = pos `mod` 64
                        in V.unsafeUpd f [(word, f V.! word .|. (1 `shiftL` bit))]

    let bloomA = foldl insertKey bloomA0 [42, 100, 500]
    let bloomB = foldl insertKey bloomB0 [500, 999]
    let merged = bloomMerge bloomA bloomB

    let bloomContains f k = let pos = abs (k * 2654435761) `mod` (V.length f * 64)
                                word = pos `quot` 64
                                bit = pos `mod` 64
                            in testBit (f V.! word) bit

    putStrLn $ "Bloom 42 in merged:   " ++ show (bloomContains merged 42)
    putStrLn $ "Bloom 500 in merged:  " ++ show (bloomContains merged 500)
    putStrLn $ "Bloom 999 in merged:  " ++ show (bloomContains merged 999)
    putStrLn $ "Bloom 9999 in merged: " ++ show (bloomContains merged 9999)

    -- Eisenstein norms
    let norms = map (uncurry eisensteinNorm) [(3,0), (0,1), (2,-1), (-1,2), (5,5)]
    let labels = ["N(3,0)", "N(0,1)", "N(2,-1)", "N(-1,2)", "N(5,5)"]
    mapM_ (\(l,v) -> putStrLn $ l ++ " = " ++ show v) (zip labels norms)

    -- Verify
    let assert cond msg = if cond then return () else error $ "ASSERTION FAILED: " ++ msg
    assert (constraintCheck lower upper pass) "constraint check pass"
    assert (not $ constraintCheck lower upper fail) "constraint check fail"
    assert (bloomContains merged 42) "bloom 42"
    assert (bloomContains merged 500) "bloom 500"
    assert (bloomContains merged 999) "bloom 999"
    assert (not $ bloomContains merged 9999) "bloom 9999 absent"
    assert (eisensteinNorm 3 0 == 9) "N(3,0)"
    assert (eisensteinNorm 0 1 == 1) "N(0,1)"
    assert (eisensteinNorm 2 (-1) == 7) "N(2,-1)"
    assert (eisensteinNorm (-1) 2 == 7) "N(-1,2)"
    assert (eisensteinNorm 5 5 == 25) "N(5,5)"

    putStrLn "\nAll assertions passed."
