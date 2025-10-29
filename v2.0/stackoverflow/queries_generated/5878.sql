-- {"query": "5878.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1028} 
WITH
-- sample aggregated activity per user with complex joins and windowing
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(u.WebsiteUrl, '') AS Website,
    -- total posts by user (all post types)
    COUNT(p.Id) AS TotalPosts,
    -- distinct tags the user has posted about (from Questions only, via Posts and Tags)
    COUNT(DISTINCT t.TagName) AS DistinctTagsUsed,
    -- score-weighted activity: sum of post scores modulo some computed metric
    SUM(COALESCE(p.Score, 0)) AS ScoreSum,
    -- last activity date from posts or comments or votes
    GREATEST(
      COALESCE(p.LastActivityDate, '1900-01-01'),
      COALESCE(c.CreationDate, '1900-01-01'),
      COALESCE(v.CreationDate, '1900-01-01')
    ) AS LastActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Tags t ON t.Id = p.Tags -- simplistic alignment for benchmarking; may be null
  WHERE u.Id > 0
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Location, u.Views, u.UpVotes, u.DownVotes, u.WebsiteUrl
),
-- correlated subquery to fetch a per-user hot tag metric from Tag Wikis
HotTagMetrics AS (
  SELECT
    u.Id AS UserId,
    (
      SELECT COUNT(*)::int
      FROM Posts q
      JOIN Tags tg ON tg.Id = ANY(string_to_array(q.Tags, '>')::int[])
      WHERE q.OwnerUserId = u.Id AND q.PostTypeId = 1
        AND q.ViewCount > 100
    ) AS HotTagPostCount
  FROM Users u
)
, -- windowed ranking by ScoreSum with NULL-safe expressions
RankedUsers AS (
  SELECT
    us.*,
    ht.HotTagPostCount,
    ROW_NUMBER() OVER (
      ORDER BY
        COALESCE(us.ScoreSum, 0) * 2
        + COALESCE(ht.HotTagPostCount, 0)
        + (CASE WHEN us.Reputation > 1000 THEN 5 ELSE 0 END)
        DESC
    ) AS RankWithinBenchmark
  FROM UserStats us
  LEFT JOIN HotTagMetrics ht ON ht.UserId = us.UserId
)
, -- elaborate post-type based cross-join to generate a heavy derived dataset
Derived AS (
  SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalPosts,
    ru.DistinctTagsUsed,
    ru.ScoreSum,
    ru.LastActivity,
    ru.HotTagPostCount,
    CASE
      WHEN ru.TotalPosts > 100 THEN 'VeryActive'
      WHEN ru.TotalPosts > 50 THEN 'Active'
      ELSE 'Casual'
    END AS ActivityBand,
    CASE
      WHEN ru.Reputation > 5000 THEN 'PowerUser'
      WHEN ru.Reputation > 1000 THEN 'RisingStar'
      ELSE 'Newbie'
    END AS UserTier
  FROM RankedUsers ru
  LEFT JOIN PostHistory ph ON ph.UserId = ru.UserId
  LEFT JOIN Posts p ON p.Id = ph.PostId
  WHERE COALESCE(ru.ScoreSum,0) > 0
)
SELECT
  d.UserId,
  d.DisplayName,
  d.Reputation,
  d.TotalPosts,
  d.DistinctTagsUsed,
  d.ScoreSum,
  d.LastActivity,
  d.HotTagPostCount,
  d.ActivityBand,
  d.UserTier,
  -- a new derived column with complex expression
  (COALESCE(d.ScoreSum,0) * 3
   + COALESCE(d.HotTagPostCount,0) * 7
   - COALESCE(pv.BountyAmount,0)) AS BenchmarkScore
FROM Derived d
LEFT JOIN Votes pv ON pv.UserId = d.UserId AND pv.VoteTypeId = 8
LEFT JOIN Posts p ON p.OwnerUserId = d.UserId
GROUP BY
  d.UserId, d.DisplayName, d.Reputation, d.TotalPosts, d.DistinctTagsUsed,
  d.ScoreSum, d.LastActivity, d.HotTagPostCount, d.ActivityBand, d.UserTier
ORDER BY BenchmarkScore DESC
LIMIT 100;