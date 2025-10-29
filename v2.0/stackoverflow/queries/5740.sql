WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    AVG(COALESCE(p.Score,0)) AS AvgPostScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
recent_activity AS (
  SELECT
    u.Id AS UserId,
    MAX(p.LastActivityDate) AS LastActivity,
    MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) AS LastUpvote
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id
),
badge_activity AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS Badges
  FROM Badges b
  GROUP BY b.UserId
),
complex_post_stats AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
    CASE
      WHEN p.PostTypeId = 1 THEN 'Question'
      WHEN p.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    MAX(CASE WHEN c.Id IS NOT NULL THEN c.Id END) AS HasComments
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Title, p.Tags, p.Score, p.ViewCount, p.LastActivityDate, p.AcceptedAnswerId
),
joined_links AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
high_complex AS (
  SELECT
    cp.PostId,
    cp.OwnerUserId,
    cp.Title,
    cp.Tags,
    cp.Score,
    cp.ViewCount,
    cp.UpVotes,
    cp.DownVotes,
    cp.PostKind,
    cp.HasComments,
    ARRAY_AGG(DISTINCT bl.LinkTypeName) AS LinkTypes
  FROM complex_post_stats cp
  LEFT JOIN joined_links bl ON bl.PostId = cp.PostId
  GROUP BY cp.PostId, cp.OwnerUserId, cp.Title, cp.Tags, cp.Score, cp.ViewCount, cp.UpVotes, cp.DownVotes, cp.PostKind, cp.HasComments
)
SELECT
  hu.UserId,
  hu.DisplayName,
  hu.Reputation,
  hu.QuestionCount,
  hu.TotalPosts,
  hu.AvgPostScore,
  ra.LastActivity,
  ba.BadgeCount,
  ba.Badges,
  ra.LastUpvote,
  hc.PostId,
  hc.Title AS PostTitle,
  hc.Tags,
  hc.Score AS PostScore,
  hc.ViewCount AS PostViews,
  hc.PostKind,
  hc.LinkTypes
FROM top_users hu
LEFT JOIN recent_activity ra ON ra.UserId = hu.UserId
LEFT JOIN badge_activity ba ON ba.UserId = hu.UserId
LEFT JOIN high_complex hc ON hc.OwnerUserId = hu.UserId
WHERE hu.Reputation > 100
  AND hu.TotalPosts > 5
ORDER BY hu.Reputation DESC, hu.TotalPosts DESC
LIMIT 100;