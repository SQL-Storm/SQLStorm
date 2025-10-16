-- {"query": "14080.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 189135, "output_tokens": 81838} 
WITH cte_user_stats AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COUNT(b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
cte_post_stats AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    CASE WHEN p.ClosedDate IS NOT NULL THEN c.Name ELSE NULL END AS CloseReason,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned' ELSE NULL END AS PostStatus
  FROM Posts p
  LEFT JOIN CloseReasonTypes c ON CAST(SUBSTRING(ph.Text, 1, CHARINDEX(',', ph.Text) - 1) AS INT) = c.Id
  INNER JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
  GROUP BY
    p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, c.Name
),
cte_post_links AS (
  SELECT
    pl.Id,
    pl.CreationDate,
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkType
  FROM PostLinks pl
  INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  cs.TotalBadges,
  cs.GoldBadges,
  cs.SilverBadges,
  cs.BronzeBadges,
  ps.PostId,
  ps.PostTypeId,
  ps.CreationDate AS PostCreationDate,
  ps.Score,
  ps.ViewCount,
  ps.AnswerCount,
  ps.CommentCount,
  ps.FavoriteCount,
  ps.CloseReason,
  ps.PostStatus,
  pl.Id AS PostLinkId,
  pl.CreationDate AS PostLinkCreationDate,
  pl.RelatedPostId,
  pl.LinkType
FROM Users u
LEFT JOIN cte_user_stats cs ON u.Id = cs.UserId
LEFT JOIN cte_post_stats ps ON u.Id = ps.PostId
LEFT JOIN cte_post_links pl ON ps.PostId = pl.PostId
ORDER BY u.Reputation DESC, ps.Score DESC, pl.CreationDate DESC;