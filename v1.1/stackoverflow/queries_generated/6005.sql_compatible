WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    COALESCE(p.OwnerUserId, -1) AS EffectiveOwner,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC
    ) AS rn_by_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
Agg AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.LastActivityDate,
    rp.AcceptedAnswerId,
    rp.ParentId,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.Body,
    rp.LastEditorUserId,
    rp.LastEditDate,
    rp.ContentLicense,
    CASE
      WHEN rp.PostTypeId = 1 THEN 'Question'
      WHEN rp.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS TypeLabel
  FROM RankedPosts rp
  WHERE rp.rn_by_type = 1
)
SELECT
  a.PostId,
  a.TypeLabel,
  a.Title,
  a.Tags,
  a.CreationDate,
  a.Score,
  a.ViewCount,
  a.LastActivityDate,
  a.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  u.Location,
  u.ProfileImageUrl,
  COALESCE(wv.TotalUpVotes, 0) AS TotalUpVotes,
  COALESCE(wv.TotalDownVotes, 0) AS TotalDownVotes,
  COALESCE(vb.TotalBadges, 0) AS TotalBadges,
  vl.LastLinkDate,
  COALESCE(ll.LinkedCount, 0) AS LinkedCount,
  lnk.RelatedPostId AS LinkedToPostId,
  p2.Title AS RelatedPostTitle,
  v_agg.TotalVoteScore,
  CASE
    WHEN a.PostTypeId = 1 THEN (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = a.PostId AND pl.LinkTypeId = 1)
    ELSE 0
  END AS LinkedCountViaLinks,
  CASE
    WHEN a.PostTypeId = 1 THEN EXISTS (
      SELECT 1 FROM Votes v2 WHERE v2.PostId = a.PostId AND v2.VoteTypeId = 2
    )
    ELSE FALSE
  END AS HasUpvotes
FROM Agg a
LEFT JOIN Users u ON a.OwnerUserId = u.Id
LEFT JOIN (
  SELECT Id AS UserId, COALESCE(UpVotes,0) AS UpVotes, COALESCE(DownVotes,0) AS DownVotes
  FROM Users
) users_votes ON users_votes.UserId = a.OwnerUserId
LEFT JOIN (
  SELECT UserId, SUM(UpVotes) AS TotalUpVotes, SUM(DownVotes) AS TotalDownVotes
  FROM (
    SELECT Id AS UserId, COALESCE(UpVotes,0) AS UpVotes, COALESCE(DownVotes,0) AS DownVotes
    FROM Users
  ) uv
  GROUP BY UserId
) wv ON wv.UserId = a.OwnerUserId
LEFT JOIN (
  SELECT UserId, COUNT(*) AS TotalBadges
  FROM Badges
  GROUP BY UserId
) vb ON vb.UserId = a.OwnerUserId
LEFT JOIN (
  SELECT PostId, MAX(CreationDate) AS LastLinkDate
  FROM PostLinks
  GROUP BY PostId
) vl ON vl.PostId = a.PostId
LEFT JOIN (
  SELECT RelatedPostId, COUNT(*) AS LinkedCount
  FROM PostLinks
  GROUP BY RelatedPostId
) ll ON ll.RelatedPostId = a.PostId
LEFT JOIN Posts p2 ON p2.Id = a.ParentId
LEFT JOIN (
  SELECT PostId, RelatedPostId, LinkTypeId
  FROM PostLinks
) lnk ON lnk.PostId = a.PostId AND lnk.LinkTypeId = 1
LEFT JOIN (
  SELECT v.PostId, SUM(CASE WHEN v.VoteTypeId IN (2,5) THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS TotalVoteScore
  FROM Votes v
  GROUP BY v.PostId
) v_agg ON v_agg.PostId = a.PostId
ORDER BY a.CreationDate DESC
LIMIT 100;