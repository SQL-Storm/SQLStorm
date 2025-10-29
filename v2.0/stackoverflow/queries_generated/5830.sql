-- {"query": "5830.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1071} 
WITH
RecentUserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
PopularTags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE t.TagName IS NOT NULL
),
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    -- windowed ranking over posts by activity within the last 30 days
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        CASE WHEN p.LastActivityDate IS NULL THEN p.CreationDate ELSE p.LastActivityDate END DESC,
        p.Score DESC,
        p.ViewCount DESC
    ) AS rn_post
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
RecentPostHistory AS (
  SELECT
    ph.Id AS HistoryId,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Comment,
    ph.Text,
    ph.RevisionGUID,
    ph.ContentLicense,
    ph.UserDisplayName,
    ph.PostId IS NOT NULL AS HasPost
  FROM PostHistory ph
  WHERE ph.CreationDate >= NOW() - INTERVAL '30 days'
),
LinkGraph AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE pl.CreationDate >= NOW() - INTERVAL '60 days'
),
UserBadges AS (
  SELECT
    b.UserId,
    b.Name AS BadgeName,
    b.Date AS EarnedDate,
    b.Class,
    b.TagBased
  FROM Badges b
  WHERE b.Date >= NOW() - INTERVAL '365 days'
),
ActiveVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    vt.Name AS VoteTypeName,
    v.BountyAmount
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE v.CreationDate >= NOW() - INTERVAL '180 days'
)
SELECT
  -- Post meta
  tq.PostId,
  tq.Title,
  tq.Score AS PostScore,
  tq.ViewCount,
  tq.CreationDate AS PostCreationDate,
  tq.LastActivityDate,
  tq.OwnerUserId,
  tq.Tags,
  tq.CommentCount,
  tq.AnswerCount,
  tq.FavoriteCount,
  -- User meta
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  u.AccountId,
  -- Relationships and analytics
  ARRAY_AGG(DISTINCT lb.BadgeName) AS EarnedBadges,
  ARRAY_AGG(DISTINCT lnk.RelatedPostId) AS LinkedToPostIds,
  AVG(vs.BountyAmount) FILTER (WHERE vs.BountyAmount IS NOT NULL) AS AvgOpenBounty,
  MAX(vs.VoteTypeName) AS LatestVoteTypeName,
  (SELECT COUNT(*) FROM ActiveVotes av WHERE av.PostId = tq.PostId) AS RecentVotes
FROM TopQuestions tq
JOIN Users u ON tq.OwnerUserId = u.Id
LEFT JOIN UserBadges lb ON lb.UserId = u.Id
LEFT JOIN LinkGraph lnk ON lnk.PostId = tq.PostId
LEFT JOIN ActiveVotes vs ON vs.PostId = tq.PostId
GROUP BY
  tq.PostId,
  tq.Title,
  tq.Score,
  tq.ViewCount,
  tq.CreationDate,
  tq.LastActivityDate,
  tq.OwnerUserId,
  tq.Tags,
  tq.CommentCount,
  tq.AnswerCount,
  tq.FavoriteCount,
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  u.AccountId
HAVING
  COUNT(lb.BadgeName) > 0 -- only posts whose author earned at least one badge in period
ORDER BY
  tq.LastActivityDate DESC
LIMIT 100;