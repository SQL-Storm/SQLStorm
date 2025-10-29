-- {"query": "5264.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 865}
WITH top_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
recent_bounties AS (
  SELECT
    v.PostId,
    v.UserId AS BountyGiverId,
    v.BountyAmount,
    v.CreationDate
  FROM Votes v
  WHERE v.VoteTypeId = 8 -- BountyStart
),
recent_posts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '90' DAY)
),
post_history AS (
  SELECT
    ph.Id,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.UserId,
    ph.CreationDate,
    ph.Text,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '180' DAY)
),
complex_join AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count AS TagCount,
    t.IsModeratorOnly,
    t.IsRequired,
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate AS PostLastActivityDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.Tags AS PostTags,
    u.Id AS UserId,
    u.DisplayName AS UserDisplayName,
    u.Reputation AS UserReputation,
    COALESCE(b.Name, 'NoBadge') AS BadgeName,
    b.Class AS BadgeClass
  FROM Tags t
  LEFT JOIN Posts p ON t.WikiPostId = p.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id AND b.Name LIKE '%' || t.TagName || '%'
  WHERE t.IsModeratorOnly = FALSE
),
cte_dashboard AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.Score AS PostScore,
    p.ViewCount AS PostViews,
    p.CreationDate AS PostDate,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistoryDate,
    ph.Text AS HistoryText,
    COALESCE(rb.BountyAmount, 0) AS BountyAmount,
    rb.CreationDate AS BountyDate,
    pg.rn AS Rank
  FROM top_users u
  LEFT JOIN recent_posts p ON p.OwnerUserId = u.Id
  LEFT JOIN post_history ph ON ph.PostId = p.Id
  LEFT JOIN recent_bounties rb ON rb.PostId = p.Id
  LEFT JOIN (
    SELECT Id, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rn
    FROM Users
  ) pg ON pg.Id = u.Id
  WHERE u.Reputation > 100
)
SELECT
  cu.UserId,
  cu.DisplayName AS UserDisplayName,
  cu.Reputation,
  cu.AccountId,
  cu.PostId,
  cu.PostTitle,
  cu.PostScore,
  cu.PostViews,
  cu.PostDate,
  cu.PostHistoryTypeId,
  cu.HistoryDate,
  cu.HistoryText,
  cu.BountyAmount,
  cu.BountyDate,
  cu.Rank
FROM cte_dashboard cu
ORDER BY cu.Reputation DESC, cu.Rank ASC
LIMIT 500;