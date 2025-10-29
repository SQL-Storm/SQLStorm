WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COUNT(p.Id) FILTER (WHERE p.Id IS NOT NULL) AS PostCount,
    AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
    MIN(p.CreationDate) FILTER (WHERE p.CreationDate IS NOT NULL) AS FirstPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
tag_influence AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    COUNT(v.Id) AS VoteCount,
    AVG(v.BountyAmount) AS AvgBounty
  FROM Tags t
  LEFT JOIN Posts p ON p.Id = t.WikiPostId
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
complex_post_summary AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Tags,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    pc.PostHistoryTypeId,
    pc.RevisionGUID,
    pc.UserId AS EditorUserId,
    pc.CreationDate AS EditDate,
    pc.Text,
    pc.ContentLicense AS EditContentLicense,
    pc.Comment AS EditComment
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT
      ph.PostHistoryTypeId,
      ph.RevisionGUID,
      ph.UserId,
      ph.CreationDate,
      ph.Comment,
      ph.Text,
      ph.ContentLicense
    FROM PostHistory ph
    WHERE ph.PostId = p.Id
    ORDER BY ph.CreationDate DESC
    LIMIT 1
  ) pc ON true
  WHERE p.PostTypeId IN (1,2)
),
windowed_events AS (
  SELECT
    cs.PostId,
    cs.PostTypeId,
    cs.Title,
    cs.Score,
    cs.ViewCount,
    cs.CreationDate,
    cs.LastActivityDate,
    cs.OwnerUserId,
    cs.ParentId,
    cs.AcceptedAnswerId,
    cs.Tags,
    cs.CommentCount,
    cs.FavoriteCount,
    cs.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY cs.OwnerUserId
      ORDER BY cs.LastActivityDate DESC, cs.Score DESC
    ) AS rn_per_user,
    SUM(cs.Score) OVER (
      PARTITION BY cs.OwnerUserId
    ) AS sum_score_per_user
  FROM (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.Title,
      p.Score,
      p.ViewCount,
      p.CreationDate,
      p.LastActivityDate,
      p.OwnerUserId,
      p.ParentId,
      p.AcceptedAnswerId,
      p.Tags,
      p.CommentCount,
      p.FavoriteCount,
      p.ContentLicense
    FROM Posts p
    WHERE p.LastActivityDate > (CAST('2024-10-01' AS date) - INTERVAL '365 days')
  ) cs
),
correlated_metrics AS (
  SELECT
    w.PostId,
    w.PostTypeId,
    w.Title,
    w.Score,
    w.ViewCount,
    w.CreationDate,
    w.LastActivityDate,
    w.OwnerUserId,
    w.ParentId,
    w.AcceptedAnswerId,
    w.Tags,
    w.CommentCount,
    w.FavoriteCount,
    w.ContentLicense,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = w.PostId) AS CommentTotal,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = w.PostId AND v.VoteTypeId = 2) AS UpVotesForPost,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = w.PostId AND v.VoteTypeId = 3) AS DownVotesForPost,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = w.PostId) AS LinkCount,
    w.sum_score_per_user
  FROM windowed_events w
  WHERE w.rn_per_user = 1
  GROUP BY
    w.PostId, w.PostTypeId, w.Title, w.Score, w.ViewCount, w.CreationDate,
    w.LastActivityDate, w.OwnerUserId, w.ParentId, w.AcceptedAnswerId,
    w.Tags, w.CommentCount, w.FavoriteCount, w.ContentLicense, w.sum_score_per_user, w.rn_per_user
),
joined AS (
  SELECT
    cu.DisplayName AS UserDisplay,
    cu.Reputation AS UserReputation,
    cu.CreationDate AS UserCreation,
    cm.sum_score_per_user AS SumScoreByUser,
    cm.PostId,
    cm.Title,
    cm.Score AS PostScore,
    cm.ViewCount,
    cm.LastActivityDate,
    cm.OwnerUserId,
    cm.Tags,
    cm.CommentTotal,
    cm.UpVotesForPost,
    cm.DownVotesForPost,
    cm.LinkCount,
    tg.TagName,
    tg.Count AS TagCount,
    tg.AvgBounty,
    ROW_NUMBER() OVER (PARTITION BY cm.PostId ORDER BY cm.LastActivityDate DESC) AS rn_per_post
  FROM correlated_metrics cm
  LEFT JOIN recent_user_activity cu ON cu.UserId = cm.OwnerUserId
  LEFT JOIN tag_influence tg ON cm.Tags LIKE '%' || tg.TagName || '%'
  GROUP BY
    cu.DisplayName, cu.Reputation, cu.CreationDate, cm.sum_score_per_user,
    cm.PostId, cm.Title, cm.Score, cm.ViewCount, cm.LastActivityDate,
    cm.OwnerUserId, cm.Tags, cm.CommentTotal, cm.UpVotesForPost,
    cm.DownVotesForPost, cm.LinkCount, tg.TagName, tg.Count, tg.AvgBounty, cm.sum_score_per_user
)
SELECT
  UserDisplay,
  UserReputation,
  UserCreation,
  SumScoreByUser,
  PostId,
  Title,
  PostScore,
  ViewCount,
  LastActivityDate,
  OwnerUserId,
  Tags,
  CommentTotal,
  UpVotesForPost,
  DownVotesForPost,
  LinkCount,
  TagName,
  TagCount,
  AvgBounty
FROM joined
WHERE rn_per_post = 1
ORDER BY LastActivityDate DESC
LIMIT 200;