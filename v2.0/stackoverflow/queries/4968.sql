-- {"query": "4968.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 894}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostCounts AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      MAX(p.CreationDate) AS LatestPostDate
    FROM
      Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  RecentUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      upc.TotalPosts,
      upc.QuestionCount,
      upc.AnswerCount,
      upc.LatestPostDate,
      CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56') - u.CreationDate) / 86400 AS INTEGER) AS AccountAgeDays,
      CASE
        WHEN u.WebsiteUrl IS NULL THEN 'No Website'
        WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
        ELSE 'External'
      END AS WebsiteCategory,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRankByReputation
    FROM
      Users u
      JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
    WHERE
      u.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year') AND u.Id > 0
  )
SELECT
  ru.DisplayName,
  ru.Reputation,
  ru.AccountAgeDays,
  ru.WebsiteCategory,
  ru.UserRankByReputation,
  ru.QuestionCount,
  ru.AnswerCount,
  (
    SELECT
      COUNT(b.Id)
    FROM
      Badges b
    WHERE
      b.UserId = ru.Id AND b.Class = 1
  ) AS GoldBadgeCount,
  (
    SELECT
      COUNT(b.Id)
    FROM
      Badges b
    WHERE
      b.UserId = ru.Id AND b.Class = 2
  ) AS SilverBadgeCount,
  (
    SELECT
      COUNT(b.Id)
    FROM
      Badges b
    WHERE
      b.UserId = ru.Id AND b.Class = 3
  ) AS BronzeBadgeCount,
  rpe.PostHistoryTypeId AS LatestEditType,
  CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56') - rpe.CreationDate) / 86400 AS INTEGER) AS DaysSinceLastEdit,
  (
    SELECT
      COUNT(*)
    FROM
      Posts p_inner
    WHERE
      p_inner.OwnerUserId = ru.Id
      AND p_inner.AnswerCount > 5
      AND p_inner.Score > 10
  ) AS HighScoringAnswersPostsCount,
  COALESCE(ru.LatestPostDate, TIMESTAMP '1970-01-01') AS ProcessedLatestPostDate
FROM
  RecentUsers ru
LEFT JOIN
  RankedPostEdits rpe
ON
  ru.Id = rpe.UserId AND rpe.rn = 1
WHERE
  ru.Reputation > 1000
  AND ru.AnswerCount > ru.QuestionCount * 0.5
  AND POSITION('SQL' IN ru.DisplayName) > 0
GROUP BY
  ru.DisplayName,
  ru.Reputation,
  ru.AccountAgeDays,
  ru.WebsiteCategory,
  ru.UserRankByReputation,
  ru.QuestionCount,
  ru.AnswerCount,
  ru.Id,
  rpe.PostHistoryTypeId,
  rpe.CreationDate,
  ru.LatestPostDate
ORDER BY
  ru.Reputation DESC,
  ru.AccountAgeDays ASC;