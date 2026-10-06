"""Number analysis and benchmarking utilities.

Provides analysis of numeric sequences with performance measurement,
including sum, mean, variance, standard deviation, and quartile statistics.
"""

import math
import statistics
import time
from collections.abc import Sequence


def benchmark(func):
    """Decorator that times a function and prints its throughput."""
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        print(f"  {func.__name__}: {elapsed * 1000:.2f} ms")
        return result
    return wrapper


def describe(numbers: Sequence[float | int], label: str = "") -> dict[str, float]:
    """Compute descriptive statistics for a sequence of numbers.

    Returns a dict with count, sum, mean, variance, std_dev, min, max,
    and quartiles (Q1, Q2/median, Q3).
    """
    n = len(numbers)
    if n == 0:
        return {}

    total = sum(numbers)
    mean = total / n
    sorted_nums = sorted(numbers)

    return {
        "count": n,
        "sum": total,
        "mean": mean,
        "variance": statistics.variance(numbers, mean) if n > 1 else 0.0,
        "std_dev": statistics.stdev(numbers, mean) if n > 1 else 0.0,
        "min": sorted_nums[0],
        "max": sorted_nums[-1],
        "q1": sorted_nums[n // 4],
        "median": statistics.median(sorted_nums),
        "q3": sorted_nums[3 * n // 4],
    }


def print_stats(stats: dict[str, float], label: str = "") -> None:
    """Pretty-print a statistics dict returned by describe()."""
    tag = f" [{label}]" if label else ""
    print(f"--- Descriptive statistics{tag} ---")
    print(f"  Count:     {stats['count']}")
    print(f"  Sum:       {stats['sum']:.4f}")
    print(f"  Mean:      {stats['mean']:.4f}")
    print(f"  Variance:  {stats['variance']:.4f}")
    print(f"  Std Dev:   {stats['std_dev']:.4f}")
    print(f"  Min:       {stats['min']:.4f}")
    print(f"  Q1:        {stats['q1']:.4f}")
    print(f"  Median:    {stats['median']:.4f}")
    print(f"  Q3:        {stats['q3']:.4f}")
    print(f"  Max:       {stats['max']:.4f}")


# ===========================================================================
# Main analysis
# ===========================================================================

if __name__ == "__main__":
    numbers = list(range(1, 101))

    # --- 1. Sum from 1 to 100 ---
    start = time.perf_counter()
    total = sum(numbers)
    elapsed = time.perf_counter() - start
    print(f"Sum of numbers from 1 to 100 is: {total}")
    print(f"  Throughput: {1 / elapsed:,.0f} ops/sec")

    # --- 2. Odd-number analysis ---
    start = time.perf_counter()

    odd_numbers = [n for n in numbers if n % 2 != 0]
    odd_stats = describe(odd_numbers)

    # Deviations from the mean
    deviations = [n - odd_stats["mean"] for n in odd_numbers]

    elapsed = time.perf_counter() - start

    print_stats(odd_stats, "odd numbers")
    print(f"  Deviations from mean: {deviations}")
    ops = 3  # list comprehension, describe(), deviations
    print(f"  Throughput: {ops / elapsed:,.0f} ops/sec")

    # --- 3. Even-number analysis ---
    start = time.perf_counter()

    even_numbers = [n for n in numbers if n % 2 == 0]
    even_stats = describe(even_numbers)

    elapsed = time.perf_counter() - start

    print_stats(even_stats, "even numbers")
    ops = 2  # list comprehension + describe()
    print(f"  Throughput: {ops / elapsed:,.0f} ops/sec")

    # --- 4. Full-set statistics ---
    full_stats = describe(numbers)
    print_stats(full_stats, "all numbers 1-100")

    # --- 5. Prime-number analysis ---
    def is_prime(n: int) -> bool:
        if n < 2:
            return False
        if n < 4:
            return True
        if n % 2 == 0 or n % 3 == 0:
            return False
        # Check divisors of the form 6k ± 1 up to sqrt(n)
        limit = int(math.isqrt(n))
        for d in range(5, limit + 1, 6):
            if n % d == 0 or n % (d + 2) == 0:
                return False
        return True

    start = time.perf_counter()

    prime_numbers = [n for n in numbers if is_prime(n)]
    prime_stats = describe(prime_numbers)

    elapsed = time.perf_counter() - start

    print_stats(prime_stats, "prime numbers")
    ops = 2
    print(f"  Throughput: {ops / elapsed:,.0f} ops/sec")