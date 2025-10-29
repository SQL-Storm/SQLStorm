-- {"query": "5670.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1074} 
-- Benchmark heavy query combining CTEs, window functions, subqueries, and several joins
WITH
/* 1) Latest post activity per user (row_number to pick latest) */
LatestActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC, p.CreationDate DESC) AS rn
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.AccountId IS NOT NULL
),
/* 2) Compute activity scoreboard with weighted scores across post types and votes */
WeightedActivity AS (
  SELECT
    a.UserId,
    a.DisplayName,
    a.Reputation,
    COUNT(*) AS TotalPosts,
    SUM(CASE WHEN a.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN a.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    -- incorporate score, views, and vote hints
    SUM(COALESCE(p.Score,0)) AS ScoreSum,
    SUM(COALESCE(p.ViewCount,0)) AS ViewCountSum,
    SUM(COALESCE(v.BountyAmount,0)) AS BountyTotal,
    -- weighted composite
    SUM(
      CASE
        WHEN p.PostTypeId = 1 THEN COALESCE(p.Score,0) * 2 + COALESCE(p.ViewCount,0) * 0.5
        WHEN p.PostTypeId = 2 THEN COALESCE(p.Score,0) * 1.5 + COALESCE(p.ViewCount,0) * 0.3
        ELSE COALESCE(p.Score,0)
      END
    ) AS WeightedScore
  FROM LatestActivity a
  LEFT JOIN Posts p ON p.Id = a.PostId
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY a.UserId, a.DisplayName, a.Reputation
),
/* 3) Tag-based activity probing using string processing and NULL handling */
TagProfiling AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    t.TagName,
    COUNT(*) AS TagUsageCount,
    MAX(p.LastActivityDate) AS LastTagActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN UNNEST(string_to_array(p.Tags, '>')) AS t(TagName)
        ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName, t.TagName
),
/* 4) Complex correlated subquery to fetch the most recent close reason per user posts */
RecentCloseReasons AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    (SELECT cr.Name
     FROM PostHistory ph
     JOIN CloseReasonTypes cr ON cr.Id = CAST(CASE WHEN ph.Comment IS NOT NULL THEN ph.Comment ELSE NULL END AS smallint)
     WHERE ph.PostId = p.Id
     ORDER BY ph.CreationDate DESC
     LIMIT 1) AS LastCloseReason
  FROM Posts p
  WHERE p.ClosedDate IS NOT NULL
)
/* 5) Final aggregation combining everything, with an outer join to include users with sparse data */
SELECT
  w.UserId,
  w.DisplayName,
  w.Reputation,
  w.TotalPosts,
  w.Questions,
  w.Answers,
  w.ScoreSum,
  w.ViewCountSum,
  w.BountyTotal,
  w.WeightedScore,
  ARRAY_AGG(DISTINCT tp.TagName) FILTER (WHERE tp.TagName IS NOT NULL) AS TopTags,
  pc.LastCloseReason,
  ra.PostId AS RecentPostId,
  ra.Title AS RecentPostTitle,
  ra.LastActivityDate AS RecentPostActivity
FROM WeightedActivity w
LEFT JOIN (
  SELECT
    u.Id AS UserId,
    p.Id AS PostId,
    p.Title,
    p.LastActivityDate
  FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate = (
    SELECT MAX(pp.LastActivityDate)
    FROM Posts pp
    WHERE pp.OwnerUserId = u.Id
  )
) ra ON ra.UserId = w.UserId
LEFT JOIN RecentCloseReasons pc ON TRUE
LEFT JOIN TagProfiling tp ON tp.UserId = w.UserId
WHERE w.Reputation > 0
GROUP BY
  w.UserId,
  w.DisplayName,
  w.Reputation,
  w.TotalPosts,
  w.Questions,
  w.Answers,
  w.ScoreSum,
  w.ViewCountSum,
  w.BountyTotal,
  w.WeightedScore,
  pc.LastCloseReason,
  ra.PostId,
  ra.Title,
  ra.LastActivityDate
ORDER BY w.WeightedScore DESC NULLS LAST
LIMIT 100;