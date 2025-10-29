-- {"query": "5374.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1064} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    u.Reputation,
    u.DisplayName AS OwnerName,
    -- compute a robust rolling metric combining score, views, and reputation
    (p.Score * 2.0 + p.ViewCount * 0.5 + COALESCE(u.Reputation, 0) * 0.01) AS EngagementScore,
    -- window function: rank posts per day by EngagementScore
    ROW_NUMBER() OVER (
      PARTITION BY CAST(p.CreationDate AS DATE)
      ORDER BY
        (p.Score * 2.0 + p.ViewCount * 0.5 + COALESCE(u.Reputation, 0) * 0.01) DESC,
        p.LastActivityDate DESC
    ) AS DayRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE p.PostTypeId IN (1, 2) -- questions and answers
    AND p.CreationDate >= timestamp '2020-01-01'
),
filter_for_benchmark AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.EngagementScore,
    rp.DayRank,
    rp.Reputation,
    rp.OwnerName,
    rp.Body,
    rp.LastActivityDate
  FROM ranked_posts rp
  WHERE rp.DayRank <= 100 -- top 100 per day
    -- complicated predicate: ensure high-quality with multiple signals
    AND rp.Score > 0
    AND rp.ViewCount > 50
    AND rp.Reputation IS NOT NULL
),
correlated_subquery AS (
  SELECT
    f.postid,
    f.Title,
    f.Tags,
    f.CreationDate,
    f.ViewCount,
    f.EngagementScore,
    f.DayRank,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = f.PostId AND c.Score >= 1) AS PositiveComments,
    (SELECT AVG(c.Score) FROM Comments c WHERE c.PostId = f.PostId) AS AvgCommentScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = f.PostId AND v.VoteTypeId = 2) AS UpVotesOnPost,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = f.PostId AND v.VoteTypeId = 3) AS DownVotesOnPost
  FROM filter_for_benchmark f
),
outer_join_example AS (
  SELECT
    c.postid,
    c.Title,
    c.Tags,
    c.CreationDate,
    c.ViewCount,
    c.EngagementScore,
    c.DayRank,
    c.PositiveComments,
    c.AvgCommentScore,
    c.UpVotesOnPost,
    c.DownVotesOnPost,
    CASE
      WHEN c.UpVotesOnPost >= 5 AND c.DownVotesOnPost <= 2 THEN 'Healthy'
      WHEN c.UpVotesOnPost < 5 AND c.DownVotesOnPost > 2 THEN 'Unhealthy'
      ELSE 'Moderate'
    END AS QualityLabel
  FROM correlated_subquery c
  LEFT JOIN (SELECT DISTINCT PostId FROM Votes WHERE VoteTypeId = 1) v ON c.PostId = v.PostId
  -- left join with a derived set of posts that have a CommunityOwnedDate to exercise NULL handling
  LEFT JOIN Posts po ON c.PostId = po.Id
  WHERE po.CommunityOwnedDate IS NULL OR po.CommunityOwnedDate > po.CreationDate
),
window_and_aggregation AS (
  SELECT
    postid,
    Title,
    Tags,
    CreationDate,
    ViewCount,
    EngagementScore,
    DayRank,
    PositiveComments,
    AvgCommentScore,
    UpVotesOnPost,
    DownVotesOnPost,
    QualityLabel,
    -- complex calculation: normalized score with NULL-safe math
    CASE
      WHEN AvgCommentScore IS NULL THEN EngagementScore
      ELSE (EngagementScore + (PositiveComments * 0.5) + (AvgCommentScore * 1.25))
    END AS BenchmarkScore
  FROM outer_join_example
)
SELECT
  postid,
  Title,
  Tags,
  CreationDate,
  ViewCount,
  EngagementScore,
  DayRank,
  PositiveComments,
  AvgCommentScore,
  UpVotesOnPost,
  DownVotesOnPost,
  QualityLabel,
  BenchmarkScore
FROM window_and_aggregation
ORDER BY BenchmarkScore DESC
LIMIT 500;