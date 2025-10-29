-- {"query": "5831.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 786} 
WITH ranked_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY CASE
        WHEN u.Reputation >= 20000 THEN 'elite'
        WHEN u.Reputation BETWEEN 1000 AND 19999 THEN 'veteran'
        WHEN u.Reputation BETWEEN 100 AND 999 THEN 'regular'
        ELSE 'new'
      END
      ORDER BY u.Reputation DESC, u.LastAccessDate DESC
    ) AS rn_in_partition
  FROM Users u
),
elite_cohort AS (
  SELECT Id, DisplayName, Reputation, CreationDate, LastAccessDate
  FROM ranked_users
  WHERE rn_in_partition = 1
    AND (CASE
           WHEN Reputation >= 20000 THEN 'elite'
           WHEN Reputation BETWEEN 1000 AND 19999 THEN 'veteran'
           WHEN Reputation BETWEEN 100 AND 999 THEN 'regular'
           ELSE 'new'
         END = 'elite'
       )
),
recent_activity AS (
  SELECT
    p.OwnerUserId,
    COUNT(*) AS activity_count,
    MAX(p.LastActivityDate) AS last_activity
  FROM Posts p
  GROUP BY p.OwnerUserId
),
top_posts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Tags,
    p.PostTypeId,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.ViewCount > 0
    AND p.Body ~ '<code>' -- rough indicator of rich content
),
complex_filtered AS (
  SELECT
    tp.PostId,
    tp.OwnerUserId,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.CreationDate,
    tp.Tags,
    tp.PostTypeId,
    ec.activity_count,
    ec.last_activity,
    u.Reputation,
    u.Location,
    u.DisplayName
  FROM top_posts tp
  LEFT JOIN recent_activity ra ON tp.OwnerUserId = ra.OwnerUserId
  LEFT JOIN elite_cohort u ON tp.OwnerUserId = u.Id
  LEFT JOIN recent_activity ec ON tp.OwnerUserId = ec.OwnerUserId
  WHERE tp.rn <= 5
    AND (tp.Score > 10 OR tp.ViewCount > 1000)
    AND (tp.Tags ~ '.*<python>.*' OR tp.Tags ~ '.*<sql>.*')
),
aggregate AS (
  SELECT
    cf.PostId,
    cf.OwnerUserId,
    cf.Title,
    cf.Score,
    cf.ViewCount,
    cf.CreationDate,
    cf.Tags,
    cf.Reputation,
    cf.Location,
    cf.DisplayName,
    cf.activity_count,
    cf.last_activity,
    COUNT(*) OVER () AS total_rows
  FROM complex_filtered cf
)
SELECT
  a.PostId,
  a.OwnerUserId,
  a.Title,
  a.Score,
  a.ViewCount,
  a.CreationDate,
  a.Tags,
  a.Reputation,
  a.Location,
  a.DisplayName,
  a.activity_count,
  a.last_activity,
  a.total_rows
FROM aggregate a
ORDER BY a.Reputation DESC NULLS LAST, a.Score DESC, a.last_activity DESC
FETCH FIRST 100 ROWS ONLY;