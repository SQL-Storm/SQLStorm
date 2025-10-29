-- {"query": "5197.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 873} 
WITH ranked_users AS (
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
    u.ProfileImageUrl,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY u.Location
      ORDER BY u.Reputation DESC, u.UpVotes - u.DownVotes DESC, u.CreationDate ASC
    ) AS rn_in_location
  FROM Users u
  WHERE u.Location IS NOT NULL
),
tag_popularity AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS total_count,
    AVG(COALESCE(p.Score, 0)) AS avg_post_score
  FROM Tags t
  LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
  GROUP BY t.TagName
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.LastActivityDate IS NOT NULL
),
complex_post_history AS (
  SELECT
    ph.PostId,
    ph.Id AS HistoryId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistoryDate,
    ph.Text,
    ph.Comment,
    ph.UserId AS HistoryUserId,
    ph.UserDisplayName AS HistoryUserDisplay
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 11, 16, 24, 52, 53, 66)
),
filtered_comments AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.UserId,
    c.UserDisplayName,
    c.CreationDate,
    c.Score,
    c.Text
  FROM Comments c
  WHERE c.Text LIKE '%performance%' ESCAPE '\' OR c.Score > 0
),
delta_votes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS Deletions,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Votes v
  GROUP BY v.PostId
),
final_BASE AS (
  SELECT
    r.UserId,
    r.DisplayName,
    r.Reputation,
    r.Location,
    ra.PostId,
    ra.Title,
    ra.CreationDate AS PostDate,
    ra.LastActivityDate,
    ra.Score AS PostScore,
    dv.UpVotes,
    dv.DownVotes,
    dv.LastVoteDate
  FROM ranked_users r
  JOIN recent_activity ra ON ra.OwnerUserId = r.UserId
  LEFT JOIN delta_votes dv ON dv.PostId = ra.PostId
  WHERE r.rn_in_location = 1
)
SELECT
  fb.UserId,
  fb.DisplayName,
  fb.Reputation,
  fb.Location,
  fb.PostId,
  fb.Title,
  fb.PostDate,
  fb.LastActivityDate,
  fb.PostScore,
  fb.UpVotes,
  fb.DownVotes,
  fb.LastVoteDate,
  (COALESCE(tag_pop.total_count, 0) * 1.0) AS TagPopularity,
  (EXISTS (SELECT 1 FROM complex_post_history cph WHERE cph.PostId = fb.PostId)) AS HasHistory,
  (SELECT COUNT(*) FROM filtered_comments fc WHERE fc.PostId = fb.PostId) AS CommentEngagement
FROM final_BASE fb
LEFT JOIN tag_popularity tag_pop ON 1 = 1
ORDER BY fb.Reputation DESC, fb.PostDate DESC
LIMIT 100;