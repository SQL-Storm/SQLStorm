WITH UserPostInteractions AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPostsCreated,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    COUNT(DISTINCT ph.Id) AS TotalHistoryEntries,
    SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS BodyEdits,
    SUM(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
    SUM(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits,
    SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPosts,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Posts p
    ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c
    ON u.Id = c.UserId
  LEFT JOIN Votes v
    ON u.Id = v.UserId
  LEFT JOIN PostHistory ph
    ON u.Id = ph.UserId
  LEFT JOIN Badges b
    ON u.Id = b.UserId
  GROUP BY
    u.Id,
    u.DisplayName
),
PostMetrics AS (
  SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    p.Score,
    p.ViewCount,
    p.FavoriteCount,
    p.AnswerCount,
    p.CommentCount,
    p.CreationDate,
    p.LastActivityDate,
    -- Standard SQL: compute minutes between timestamps
    CAST(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 60 AS BIGINT) AS ActiveDurationMinutes,
    (
      SELECT COUNT(*)
      FROM Comments c
      WHERE c.PostId = p.Id
    ) AS CommentCountSubquery,
    (
      SELECT COUNT(*)
      FROM Votes v
      WHERE v.PostId = p.Id AND v.VoteTypeId = 2
    ) AS UpVoteCountSubquery,
    (
      SELECT COUNT(*)
      FROM Votes v
      WHERE v.PostId = p.Id AND v.VoteTypeId = 3
    ) AS DownVoteCountSubquery,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned
  FROM Posts p
  JOIN PostTypes pt
    ON p.PostTypeId = pt.Id
)
SELECT
  upi.UserId,
  upi.DisplayName,
  upi.TotalPostsCreated,
  upi.TotalQuestions,
  upi.TotalAnswers,
  upi.TotalComments,
  upi.TotalVotes,
  upi.TotalUpVotes,
  upi.TotalDownVotes,
  upi.TotalHistoryEntries,
  upi.BodyEdits,
  upi.TitleEdits,
  upi.TagEdits,
  upi.ClosedPosts,
  upi.GoldBadges,
  upi.SilverBadges,
  upi.BronzeBadges,
  pm.PostId,
  pm.PostType,
  pm.Score,
  pm.ViewCount,
  pm.FavoriteCount,
  pm.AnswerCount,
  pm.CommentCount,
  pm.CreationDate,
  pm.LastActivityDate,
  pm.ActiveDurationMinutes,
  pm.CommentCountSubquery,
  pm.UpVoteCountSubquery,
  pm.DownVoteCountSubquery,
  pm.IsClosed,
  pm.IsCommunityOwned
FROM UserPostInteractions upi
CROSS JOIN PostMetrics pm
WHERE
  upi.UserId = (
    SELECT OwnerUserId
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    ORDER BY CreationDate DESC
    LIMIT 1
  )
ORDER BY
  upi.TotalPostsCreated DESC,
  pm.Score DESC
LIMIT 100;