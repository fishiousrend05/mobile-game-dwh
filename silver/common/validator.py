# silver/common/validator.py
from dataclasses import dataclass, field
from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from utils.logger import get_logger

logger = get_logger("silver.validator", log_dir="logs/silver")


# ----------------------------------------------------------------
# Kết quả validate — không raise exception ngay
# Gom hết lỗi lại rồi report một lần
# ----------------------------------------------------------------

@dataclass
class ValidationResult:
    table_name: str
    passed:     list[str] = field(default_factory=list)
    failed:     list[str] = field(default_factory=list)

    @property
    def is_valid(self) -> bool:
        return len(self.failed) == 0

    def summary(self) -> str:
        lines = [f"\n[validator] === {self.table_name} ==="]
        for msg in self.passed:
            lines.append(f"  PASS  {msg}")
        for msg in self.failed:
            lines.append(f"  FAIL  {msg}")
        lines.append(
            f"  → {len(self.passed)} passed, {len(self.failed)} failed"
        )
        return "\n".join(lines)


# ----------------------------------------------------------------
# Các checks tái sử dụng được
# ----------------------------------------------------------------

def check_not_empty(df: DataFrame, result: ValidationResult) -> None:
    count = df.count()
    if count == 0:
        result.failed.append(f"Table is empty — 0 rows")
    else:
        result.passed.append(f"Row count: {count:,}")


def check_no_nulls(
    df: DataFrame,
    columns: list[str],
    result: ValidationResult,
) -> None:
    for col in columns:
        null_count = df.filter(F.col(col).isNull()).count()
        if null_count > 0:
            result.failed.append(
                f"NULL in '{col}': {null_count:,} rows "
                f"({null_count / df.count():.1%})"
            )
        else:
            result.passed.append(f"No nulls in '{col}'")


def check_no_duplicates(
    df: DataFrame,
    key_columns: list[str],
    result: ValidationResult,
) -> None:
    total    = df.count()
    distinct = df.dropDuplicates(key_columns).count()
    dupes    = total - distinct
    if dupes > 0:
        result.failed.append(
            f"Duplicates on {key_columns}: {dupes:,} rows"
        )
    else:
        result.passed.append(f"No duplicates on {key_columns}")


def check_accepted_values(
    df: DataFrame,
    column: str,
    accepted: list,
    result: ValidationResult,
) -> None:
    invalid = (
        df.filter(~F.col(column).isin(accepted) & F.col(column).isNotNull())
          .count()
    )
    if invalid > 0:
        result.failed.append(
            f"'{column}' has {invalid:,} values not in {accepted}"
        )
    else:
        result.passed.append(f"'{column}' values all within accepted set")


def check_value_range(
    df: DataFrame,
    column: str,
    min_val: float = None,
    max_val: float = None,
    result: ValidationResult = None,
) -> None:
    conditions = []
    if min_val is not None:
        conditions.append(F.col(column) < min_val)
    if max_val is not None:
        conditions.append(F.col(column) > max_val)

    if not conditions:
        return

    invalid = df.filter(
        F.col(column).isNotNull() & conditions[0]
        if len(conditions) == 1
        else F.col(column).isNotNull() & (conditions[0] | conditions[1])
    ).count()

    if invalid > 0:
        result.failed.append(
            f"'{column}' has {invalid:,} values outside "
            f"[{min_val}, {max_val}]"
        )
    else:
        result.passed.append(
            f"'{column}' range OK [{min_val}, {max_val}]"
        )


def check_referential_integrity(
    df_fact: DataFrame,
    df_dim: DataFrame,
    fact_key: str,
    dim_key: str,
    result: ValidationResult,
) -> None:
    """
    Kiểm tra mọi fact_key đều có record tương ứng trong dim.
    Ví dụ: mọi user_id trong fact_events phải có trong dim_users.
    """
    orphans = (
        df_fact.select(fact_key)
        .join(df_dim.select(dim_key),
              df_fact[fact_key] == df_dim[dim_key],
              how="left_anti")
        .count()
    )
    if orphans > 0:
        result.failed.append(
            f"Referential integrity: {orphans:,} '{fact_key}' "
            f"in fact not found in dim"
        )
    else:
        result.passed.append(
            f"Referential integrity OK: all '{fact_key}' found in dim"
        )


# ----------------------------------------------------------------
# Validate từng bảng Silver
# ----------------------------------------------------------------

def validate_fact_events(df: DataFrame) -> ValidationResult:
    result = ValidationResult("fact_events")

    check_not_empty(df, result)
    check_no_nulls(df, ["event_uuid", "user_id", "event_name", "event_date"], result)
    check_no_duplicates(df, ["event_uuid"], result)
    check_accepted_values(
        df, "event_name",
        accepted=["account_created", "login", "tutorial_completed",
                  "level_up", "in_app_purchase"],
        result=result,
    )
    check_accepted_values(
        df, "platform",
        accepted=["ios", "android", "unknown"],
        result=result,
    )
    check_value_range(
        df, "snapshot_level",
        min_val=1, max_val=999,
        result=result,
    )

    logger.info(result.summary())
    return result


def validate_dim_users(df: DataFrame) -> ValidationResult:
    result = ValidationResult("dim_users")

    check_not_empty(df, result)
    check_no_nulls(df, ["user_id", "account_created_at"], result)
    check_no_duplicates(df, ["user_id"], result)

    logger.info(result.summary())
    return result


def validate_fact_event_params(df: DataFrame) -> ValidationResult:
    result = ValidationResult("fact_event_params")

    check_not_empty(df, result)
    check_no_nulls(df, ["event_uuid", "user_id", "event_name"], result)
    check_no_duplicates(df, ["event_uuid"], result)
    check_value_range(
        df, "revenue_usd",
        min_val=0.0,        # revenue không thể âm
        result=result,
    )
    check_value_range(
        df, "login_streak",
        min_val=0,
        result=result,
    )

    logger.info(result.summary())
    return result


def validate_fact_event_items(df: DataFrame) -> ValidationResult:
    result = ValidationResult("fact_event_items")

    check_not_empty(df, result)
    check_no_nulls(df, ["event_uuid", "user_id", "item_id", "direction"], result)
    check_accepted_values(
        df, "direction",
        accepted=["spent", "received"],
        result=result,
    )
    check_value_range(
        df, "quantity",
        min_val=1,          # quantity phải >= 1
        result=result,
    )

    logger.info(result.summary())
    return result


# ----------------------------------------------------------------
# Validate cross-table — referential integrity
# ----------------------------------------------------------------

def validate_cross_table(
    fact_events: DataFrame,
    dim_users: DataFrame,
    fact_event_params: DataFrame,
    fact_event_items: DataFrame,
) -> ValidationResult:
    result = ValidationResult("cross_table")

    # fact_events.user_id phải có trong dim_users
    check_referential_integrity(
        fact_events, dim_users,
        fact_key="user_id", dim_key="user_id",
        result=result,
    )

    # fact_event_params.event_uuid phải có trong fact_events
    check_referential_integrity(
        fact_event_params, fact_events,
        fact_key="event_uuid", dim_key="event_uuid",
        result=result,
    )

    # fact_event_items.event_uuid phải có trong fact_events
    check_referential_integrity(
        fact_event_items, fact_events,
        fact_key="event_uuid", dim_key="event_uuid",
        result=result,
    )

    logger.info(result.summary())
    return result


# ----------------------------------------------------------------
# Entry point — validate tất cả sau khi Silver ghi xong
# ----------------------------------------------------------------

def validate_all(
    fact_events: DataFrame,
    dim_users: DataFrame,
    fact_event_params: DataFrame,
    fact_event_items: DataFrame,
    raise_on_failure: bool = True,
) -> bool:
    """
    Chạy toàn bộ validation.
    raise_on_failure=True  → pipeline dừng nếu có FAIL (dùng trong production)
    raise_on_failure=False → chỉ log warning (dùng khi debug)
    """
    results = [
        validate_fact_events(fact_events),
        validate_dim_users(dim_users),
        validate_fact_event_params(fact_event_params),
        validate_fact_event_items(fact_event_items),
        validate_cross_table(
            fact_events, dim_users,
            fact_event_params, fact_event_items
        ),
    ]

    all_passed = all(r.is_valid for r in results)
    failed     = [r for r in results if not r.is_valid]

    if all_passed:
        logger.info("[validator] All checks passed.")
    else:
        msg = (
            f"[validator] {len(failed)} table(s) failed validation: "
            f"{[r.table_name for r in failed]}"
        )
        if raise_on_failure:
            raise ValueError(msg)
        else:
            logger.warning(msg)

    return all_passed