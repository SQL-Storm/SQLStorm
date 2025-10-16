-- {"query": "18075.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 874} 

WITH
  RecentPosts AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      CreationDate,
      Score,
      AnswerCount,
      FavoriteCount,
      ROW_NUMBER() OVER (
        PARTITION BY
          OwnerUserId
        ORDER BY
          CreationDate DESC
      ) as rn
    FROM
      Posts
    WHERE
      PostTypeId = 1 AND CreationDate >= NOW() - INTERVAL '30 days'
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositivelyScoredPosts,
      MAX(CASE WHEN p.AnswerCount > 5 THEN 1 ELSE 0 END) AS HasHighlyAnsweredPosts,
      AVG(p.Score) AS AverageScore
    FROM
      Users u
      JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE
      u.Id IN (
        SELECT DISTINCT
          OwnerUserId
        FROM
          Posts
        WHERE
          CreationDate >= NOW() - INTERVAL '90 days'
      )
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation
    FROM
      Users
    WHERE
      Reputation >= 10000
  ),
  TopTagQuestions AS (
    SELECT
      p.Id,
      p.Title,
      p.Score,
      t.TagName,
      ROW_NUMBER() OVER (
        PARTITION BY
          t.TagName
        ORDER BY
          p.Score DESC
      ) as rank_in_tag
    FROM
      Posts p
      JOIN Tags t ON ',' || p.Tags || ',' LIKE '%,' || t.TagName || ',%'
    WHERE
      p.PostTypeId = 1 AND p.CreationDate >= NOW() - INTERVAL '7 days' AND t.TagName IN ('sql', 'performance', 'optimization', 'query-performance')
  )
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.TotalPosts,
  ua.PositivelyScoredPosts,
  ua.HasHighlyAnsweredQuestions,
  ua.AverageScore,
  rp.Title AS MostRecentQuestionTitle,
  rp.Score AS MostRecentQuestionScore,
  (
    SELECT
      COUNT(*)
    FROM
      Comments c
    WHERE
      c.UserId = ua.UserId
      AND c.CreationDate >= ua.LastAccessDate - INTERVAL '30 days'
  ) AS RecentCommentsCount,
  CASE
    WHEN hru.Id IS NOT NULL THEN 'High Reputation'
    ELSE 'Standard Reputation'
  END AS ReputationTier,
  CASE
    WHEN ttq.rank_in_tag <= 3 THEN 'Top Tag Question'
    ELSE 'Other Question'
  END AS TagQuestionStatus,
  COALESCE(rp.FavoriteCount, 0) AS RecentFavoriteCount
FROM
  UserActivity ua
  LEFT JOIN RecentPosts rp ON ua.UserId = rp.OwnerUserId AND rp.rn = 1
  LEFT JOIN HighReputationUsers hru ON ua.UserId = hru.Id
  LEFT JOIN TopTagQuestions ttq ON ua.UserId = (
    SELECT
      OwnerUserId
    FROM
      Posts
    WHERE
      Id = ttq.Id
  ) AND ttq.rank_in_tag <= 3
WHERE
  ua.AverageScore > 0
  OR ua.TotalPosts > 10
ORDER BY
  ua.Reputation DESC,
  ua.AverageScore DESC NULLS LAST;
