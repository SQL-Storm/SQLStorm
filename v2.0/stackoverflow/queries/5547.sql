-- {"query": "5547.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1109}
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    p.AnswerCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn_type
  FROM Posts p
  WHERE p.LastActivityDate IS NOT NULL
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
    u.WebsiteUrl,
    u.AboutMe,
    u.AccountId,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    MAX(b.Date) AS LastBadgeDate
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Views, u.UpVotes, u.DownVotes, u.ProfileImageUrl, u.Location,
    u.WebsiteUrl, u.AboutMe, u.AccountId
),
TagWeight AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn_tag
  FROM Tags t
  WHERE COALESCE(t.IsModeratorOnly, false) = false
),
VotedActivity AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    CASE
      WHEN v.VoteTypeId = 2 THEN 1
      WHEN v.VoteTypeId = 3 THEN -1
      ELSE 0
    END AS Delta,
    ROW_NUMBER() OVER (PARTITION BY v.PostId, v.VoteTypeId ORDER BY v.CreationDate DESC) AS rn_vote
  FROM Votes v
  WHERE v.CreationDate IS NOT NULL
),
Combined AS (
  SELECT
    rap.PostId,
    rap.PostTypeId,
    rap.Title,
    rap.Tags,
    rap.OwnerUserId,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    rap.CommentCount,
    rap.FavoriteCount,
    rap.AnswerCount,
    rap.ParentId,
    rap.AcceptedAnswerId,
    rap.ContentLicense,
    ur.UserId,
    ur.DisplayName AS UserDisplayName,
    ur.Reputation,
    ur.UserCreationDate,
    ur.LastAccessDate,
    ur.Location,
    ur.WebsiteUrl,
    ur.AboutMe,
    ur.AccountId,
    ub.BadgeCount,
    ub.LastBadgeDate,
    tt.TagName,
    tt.Count AS TagCount,
    va.VoteTypeId,
    va.CreationDate AS VoteDate,
    va.Delta
  FROM RecentActivePosts rap
  LEFT JOIN UserStats ur ON rap.OwnerUserId = ur.UserId
  LEFT JOIN TagWeight tt ON rap.Tags LIKE '%' || tt.TagName || '%'
  LEFT JOIN VotedActivity va ON rap.PostId = va.PostId AND va.rn_vote = 1
  LEFT JOIN (SELECT UserId, COUNT(*) AS BadgeCount, MAX(Date) AS LastBadgeDate FROM Badges GROUP BY UserId) ub
    ON rap.OwnerUserId = ub.UserId
)
SELECT
  COALESCE(rap.Title, 'Untitled') AS Title,
  rap.PostTypeId,
  rap.PostId,
  rap.LastActivityDate,
  rap.Score,
  rap.ViewCount,
  rap.CommentCount,
  rap.FavoriteCount,
  rap.AnswerCount,
  rap.ParentId,
  rap.AcceptedAnswerId,
  rap.ContentLicense,
  rap.UserDisplayName,
  rap.Reputation,
  rap.Location,
  rap.WebsiteUrl,
  rap.AboutMe,
  rap.TagName,
  rap.TagCount,
  rap.Delta,
  rap.VoteDate,
  CASE
    WHEN rap.Score > 0 AND rap.ViewCount > 100 THEN 'Hot'
    WHEN rap.Score BETWEEN -5 AND 0 THEN 'Neg'
    ELSE 'Neutral'
  END AS MomentumLabel,
  (SELECT AVG(va2.Delta) FROM VotedActivity va2 WHERE va2.PostId = rap.PostId) AS AvgVoteDelta,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rap.PostId) AS CommentCountAll,
  (rap.Score * 1.0) / NULLIF(rap.ViewCount, 0) AS ScorePerView,
  CASE
    WHEN rap.LastActivityDate < CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days' THEN true
    ELSE false
  END AS Stale
FROM Combined rap
ORDER BY rap.LastActivityDate DESC
LIMIT 100;