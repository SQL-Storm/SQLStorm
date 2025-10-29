-- {"query": "5846.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 865} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    -- explode tags and pick top 5 by post activity
    t.TagName,
    COUNT(*) AS TagUsage,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.Score) AS TotalScore
  FROM RecentActivePosts r
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(r.Tags, 2, length(r.Tags)-2), '><')) AS TagName
  ) t
  GROUP BY t.TagName
  ORDER BY TotalViews DESC
  LIMIT 5
),
TagEngagement AS (
  SELECT
    tt.TagName,
    tt.TotalViews,
    tt.TotalScore,
    CAST(tt.TotalViews AS DECIMAL(20,2)) / NULLIF(tt.TotalScore,0) AS ViewsPerScore
  FROM TopTags tt
),
CrossJoinUsers AS (
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
    u.AccountId,
    COALESCE(b.TotalBadges, 0) AS BadgeCount
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
),
FlaggedPosts AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.UserId,
    ph.CreationDate,
    ph.Comment,
    ph.Text
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13) -- close/delete/undelete style events
),
Correlation AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate AS PostCreation,
    r.LastActivityDate,
    r.OwnerUserId,
    r.Tags,
    p.PostTypeId,
    a.DisplayName AS OwnerDisplayName,
    v.TotalVotes,
    w.BountyAmount
  FROM RecentActivePosts r
  LEFT JOIN Posts p ON p.Id = r.PostId
  LEFT JOIN Users a ON a.Id = r.OwnerUserId
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = r.PostId
  LEFT JOIN Votes wv ON wv.PostId = r.PostId AND wv.VoteTypeId = 8
  LEFT JOIN (SELECT PostId, BountyAmount FROM Votes WHERE VoteTypeId = 8) w ON w.PostId = r.PostId
)
SELECT
  cr.TagName,
  cr.TotalViews,
  cr.TotalScore,
  cr.ViewsPerScore,
  cu.UserId,
  cu.DisplayName AS UserDisplayName,
  cu.Reputation,
  cu.CreationDate AS UserCreationDate,
  cu.LastAccessDate AS UserLastAccessDate,
  cu.Location,
  cr.PostId,
  cr.Title,
  cr.PostCreation,
  cr.LastActivityDate,
  cr.PostTypeId,
  cr.OwnerDisplayName,
  cr.TotalVotes,
  cr.BountyAmount
FROM
  TagEngagement cr
  CROSS JOIN LATERAL (
    SELECT TOP 1 ta.TagName
    FROM TopTags ta
    ORDER BY ta.TotalViews DESC
  ) t
  LEFT JOIN CrossJoinUsers cu ON true
ORDER BY cr.TotalViews DESC
LIMIT 100;