-- {"query": "5986.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 960} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.DeletionDate IS NULL -- if available in schema; ignore if not present
),
top_contributors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS rn
  FROM Users u
  WHERE u.Reputation IS NOT NULL
),
tag_stats AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgQuestionScore,
    AVG(p.ViewCount) AS AvgViewCount
  FROM Tags t
  LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
  WHERE t.IsModeratorOnly = 0 OR t.IsModeratorOnly IS NULL
  GROUP BY t.TagName, t.Count
),
complex_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.OwnerUserId,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS DisplayName,
    -- compute a computed metric: engagement score combining views, comments, and answers
    (COALESCE(p.ViewCount,0) * 0.5 + COALESCE(p.CommentCount,0) * 3 + COALESCE(p.AnswerCount,0) * 5) AS EngagementScore,
    -- complex predicate: posts created in last 90 days OR high engagement
    CASE
      WHEN p.CreationDate >= CURRENT_DATE - INTERVAL '90 days' THEN 1
      WHEN (COALESCE(p.ViewCount,0) > 1000 AND COALESCE(p.Score,0) > 5) THEN 1
      ELSE 0
    END AS RecentOrHighEngagement
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.CommunityOwnedDate IS NULL
),
cte_with_window AS (
  SELECT
    cp.*,
    SUM(RecentOrHighEngagement) OVER (PARTITION BY cp.OwnerUserId ORDER BY cp.CreationDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS RollingFlag,
    AVG(EngagementScore) OVER (PARTITION BY cp.OwnerUserId) AS AvgEngagementByAuthor
  FROM complex_posts cp
)
SELECT
  -- a composite, benchmark-friendly result set
  rp.PostId,
  rp.Title,
  rp.Tags,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.Score,
  rp.ViewCount,
  rp.CommentCount,
  rp.AnswerCount,
  rp.DisplayName,
  rp.EngagementScore,
  rp.RecentOrHighEngagement,
  w.RollingFlag,
  w.AvgEngagementByAuthor,
  tc.TagName,
  tc.TagCount,
  tc.AvgQuestionScore,
  tc.AvgViewCount,
  tu.UserId AS TopContributorUserId,
  tu.DisplayName AS TopContributorDisplayName,
  tu.Reputation AS TopContributorReputation
FROM cte_with_window w
LEFT JOIN RecentQuestions rp ON rp.Id = w.Id
LEFT JOIN top_contributors tu ON tu.UserId = w.OwnerUserId
LEFT JOIN tag_stats tc ON tc.TagName = ANY(string_to_array(substr(w.Tags, 2, length(w.Tags)-2), '><'))
WHERE
  w.RecentOrHighEngagement = 1
  AND w.RollingFlag > 0
ORDER BY w.AvgEngagementByAuthor DESC, w.EngagementScore DESC
LIMIT 100;