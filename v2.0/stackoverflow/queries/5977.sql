-- {"query": "5977.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 870}
WITH
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
    MAX(p.CreationDate) AS LastPostDate,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE NULL END), 0) AS TotalBounty
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
RecentActivity AS (
  SELECT
    a.UserId,
    a.DisplayName,
    a.Reputation,
    a.UserCreationDate,
    a.LastAccessDate,
    a.QuestionCount,
    a.AnswerCount,
    a.LastPostDate,
    a.TotalBounty,
    CASE WHEN a.LastPostDate IS NULL THEN 0 ELSE EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - a.LastPostDate)) END AS RecencySeconds,
    (a.QuestionCount + a.AnswerCount) * 100 + COALESCE(a.TotalBounty, 0) AS ProductivityScore
  FROM UserActivity a
),
TopPerformers AS (
  SELECT
    ra.UserId,
    ra.DisplayName,
    ra.Reputation,
    ra.RecencySeconds,
    ra.ProductivityScore,
    ra.LastPostDate
  FROM RecentActivity ra
  WHERE
    ra.Reputation > 1000
    OR ra.ProductivityScore > 1000
    OR EXISTS (
      SELECT 1
      FROM Posts p
      WHERE p.OwnerUserId = ra.UserId
        AND p.PostTypeId = 1
        AND p.Score > 50
        AND p.CreationDate > (DATE '2024-10-01' - INTERVAL '365 days')
    )
),
Cohort AS (
  SELECT UserId, DisplayName, Reputation, LastPostDate, ProductivityScore
  FROM TopPerformers
  UNION
  SELECT u.Id, u.DisplayName, u.Reputation, NULL AS LastPostDate, 0 AS ProductivityScore
  FROM Users u
  WHERE u.Reputation BETWEEN 500 AND 1000
),
FinalRank AS (
  SELECT
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.LastPostDate,
    c.ProductivityScore,
    ROW_NUMBER() OVER (
      PARTITION BY CASE WHEN c.LastPostDate IS NULL THEN 0 ELSE 1 END
      ORDER BY c.Reputation DESC, c.ProductivityScore DESC, c.LastPostDate DESC
    ) AS RankWithinGroup
  FROM Cohort c
)
SELECT
  fr.UserId,
  fr.DisplayName,
  fr.Reputation,
  fr.LastPostDate,
  fr.ProductivityScore,
  fr.RankWithinGroup,
  (SELECT AVG(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)))
     FROM Posts p
     WHERE p.OwnerUserId = fr.UserId) AS AvgPostAgeSeconds,
  (SELECT COUNT(*) FROM (
     SELECT trim(tag) AS tag
     FROM Posts p
     CROSS JOIN LATERAL (
       SELECT value AS tag FROM (
         SELECT regexp_split_to_table(p.Tags, ',') AS value
       ) s
     ) sub
     WHERE p.OwnerUserId = fr.UserId AND p.Tags IS NOT NULL
  ) t) AS TagDiversity
FROM FinalRank fr
ORDER BY fr.RankWithinGroup ASC
LIMIT 100;