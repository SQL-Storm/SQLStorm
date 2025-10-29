-- {"query": "5988.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 881} 
WITH TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    -- computed metrics
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.ViewCount > 0
),
RecentActivity AS (
  SELECT
    t.PostId,
    t.Title,
    t.CreationDate,
    t.LastActivityDate,
    t.ViewCount,
    t.Score,
    t.OwnerUserId,
    t.CommentCount,
    t.FavoriteCount,
    t.Tags,
    t.ContentLicense,
    -- windowed rank per user by last activity
    ROW_NUMBER() OVER (PARTITION BY t.OwnerUserId ORDER BY t.LastActivityDate DESC, t.Score DESC) AS user_rank
  FROM TopPosts t
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.EmailHash,
    u.AccountId,
    -- activity score integrating multiple factors
    (COALESCE(u.Views,0) * 1.0
     + COALESCE(u.UpVotes,0) * 2.0
     - COALESCE(u.DownVotes,0) * 1.5) AS ActivityScore
  FROM Users u
),
Combined AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.ViewCount,
    r.Score,
    r.OwnerUserId,
    r.CommentCount,
    r.FavoriteCount,
    r.Tags,
    r.ContentLicense,
    u.UserId,
    u.DisplayName AS UserDisplayName,
    u.Reputation,
    u.UserCreationDate,
    u.LastAccessDate,
    u.ActivityScore,
    u.user_rank
  FROM RecentActivity r
  LEFT JOIN UserStats u
    ON r.OwnerUserId = u.UserId
),
TagPairs AS (
  SELECT
    c.*,
    -- split tag list into individual tags for cross-join-ish analysis
    unnest(string_to_array(substring(c.Tags, 2, length(c.Tags)-2), '><')) AS Tag
  FROM Combined c
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.LastActivityDate,
  c.ViewCount,
  c.Score,
  c.OwnerUserId,
  c.CommentCount,
  c.FavoriteCount,
  c.Tags,
  c.ContentLicense,
  c.UserId,
  c.UserDisplayName,
  c.Reputation,
  c.UserCreationDate,
  c.LastAccessDate,
  c.ActivityScore,
  c.user_rank,
  t.Tag,
  (CASE
     WHEN c.Reputation IS NULL THEN 0
     ELSE c.Reputation * 0.75
   END) AS AdjustedReputation,
  (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = c.PostId AND v.VoteTypeId = 9) AS AvgBountyOnPost,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = c.OwnerUserId AND p2.PostTypeId = 1) AS OtherQuestionsByUser,
  (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = c.PostId) AS LastVoteDate
FROM Combined c
LEFT JOIN TagPairs tp ON tp.PostId = c.PostId
LEFT JOIN (SELECT 1 AS dummy) AS d ON true
ORDER BY c.user_rank ASC, c.LastActivityDate DESC, c.ViewCount DESC
LIMIT 100;