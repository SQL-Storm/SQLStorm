-- {"query": "20055.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1303} 
WITH UserActivitySummary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    SUM(p.Score) AS TotalPostScore,
    SUM(p.ViewCount) AS TotalViewCount,
    SUM(p.FavoriteCount) AS TotalFavoriteCount,
    AVG(p.Score) AS AvgPostScore,
    (
      SELECT
        COUNT(*)
      FROM
        Badges b
      WHERE
        b.UserId = u.Id
    ) AS BadgeCount,
    (
      SELECT
        COUNT(*)
      FROM
        Comments c
      WHERE
        c.UserId = u.Id
    ) AS CommentCount
  FROM
    Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE
    u.Id > 0
    AND u.Reputation > 100
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe
), PostAnalysis AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Score,
    p.ParentId,
    p.CreationDate AS PostCreationDate,
    p.Tags,
    q.CreationDate AS QuestionCreationDate,
    LEAD(p.CreationDate, 1) OVER (PARTITION BY p.ParentId ORDER BY p.CreationDate) AS NextAnswerDate,
    RANK() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS AnswerRankByScore,
    EXTRACT(
      EPOCH
      FROM
        (p.CreationDate - q.CreationDate)
    ) / 3600 AS HoursToAnswer
  FROM
    Posts p
    JOIN Posts q ON p.ParentId = q.Id
  WHERE
    p.PostTypeId = 2
    AND p.OwnerUserId IS NOT NULL
)
SELECT
  uas.DisplayName,
  uas.Reputation,
  uas.TotalPosts,
  uas.QuestionCount,
  uas.AnswerCount,
  uas.BadgeCount,
  uas.CommentCount,
  pa.TopAnswerScore,
  pa.AvgHoursToAnswer,
  pa.BestAnswerRank,
  CASE
    WHEN uas.Reputation > 100000 THEN 'Diamond User'
    WHEN uas.Reputation > 20000 THEN 'Gold User'
    WHEN uas.Reputation > 5000 THEN 'Silver User'
    ELSE 'Bronze User'
  END AS UserTier,
  (
    uas.Reputation / NULLIF(
      EXTRACT(
        EPOCH
        FROM
          (cast('2024-10-01 12:34:56' as timestamp) - uas.CreationDate)
      ) / 86400.0,
      0
    )
  ) AS ReputationPerDay,
  LOWER(
    SUBSTRING(
      COALESCE(uas.AboutMe, 'No bio available.'),
      1,
      50
    )
  ) || '...' AS AboutMeSnippet,
  (
    SELECT
      v.VoteTypeId
    FROM
      Votes v
    WHERE
      v.UserId = uas.UserId
    GROUP BY
      v.VoteTypeId
    ORDER BY
      COUNT(*) DESC
    LIMIT
      1
  ) AS MostCommonVoteTypeId
FROM
  UserActivitySummary uas
  LEFT JOIN (
    SELECT
      OwnerUserId,
      MAX(Score) AS TopAnswerScore,
      AVG(HoursToAnswer) AS AvgHoursToAnswer,
      MIN(AnswerRankByScore) AS BestAnswerRank
    FROM
      PostAnalysis
    WHERE
      AnswerRankByScore <= 3
    GROUP BY
      OwnerUserId
  ) pa ON uas.UserId = pa.OwnerUserId
WHERE
  uas.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
  AND uas.TotalPosts > (
    SELECT
      AVG(TotalPosts) * 1.5
    FROM
      UserActivitySummary
  )
  AND uas.Location IS NOT NULL
  AND uas.UserId IN (
    SELECT
      DISTINCT OwnerUserId
    FROM
      Posts
    WHERE
      Tags LIKE '%<sql>%'
      AND Score > 10
      AND OwnerUserId IS NOT NULL
  )
UNION
SELECT
  u.DisplayName,
  u.Reputation,
  0,
  0,
  0,
  0,
  0,
  NULL,
  NULL,
  NULL,
  'Inactive Veteran',
  0.0,
  'N/A',
  NULL
FROM
  Users u
WHERE
  u.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '10 years'
  AND u.LastAccessDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 years'
  AND u.Reputation > 10000
  AND NOT EXISTS (
    SELECT
      1
    FROM
      Posts p
    WHERE
      p.OwnerUserId = u.Id
      AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 years'
  )
ORDER BY
  Reputation DESC,
  TotalPosts DESC
LIMIT
  500;