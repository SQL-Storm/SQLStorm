WITH recent_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate DESC) AS rn
  FROM Users u
),
tag_pop AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS total_posts,
    AVG(u.Reputation) AS avg_user_rep
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE t.IsModeratorOnly = FALSE
  GROUP BY t.TagName
),
complex_post_stats AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountInline
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
),
latest_edits AS (
  SELECT
    p.Id,
    p.Title,
    ph.PostId,
    ph.CreationDate AS EditDate,
    ph.UserId AS EditorId,
    ph.Comment AS EditComment
  FROM Posts p
  JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6,24,37,38)
  WHERE ph.CreationDate = (
    SELECT MAX(ph2.CreationDate)
    FROM PostHistory ph2
    WHERE ph2.PostId = p.Id
      AND ph2.PostHistoryTypeId IN (4,5,6,24,37,38)
  )
),
correlated_votes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Votes v
  GROUP BY v.PostId
),
hotness AS (
  SELECT
    t.TagName,
    t.total_posts,
    t.avg_user_rep,
    ROW_NUMBER() OVER (ORDER BY t.total_posts DESC, t.avg_user_rep DESC) AS rn
  FROM tag_pop t
)
SELECT
  rp.rn AS ranking_group,
  cu.DisplayName AS TopUser,
  cu.Reputation AS TopReputation,
  cp.PostId,
  cp.PostTypeId,
  cp.Title AS PostTitle,
  cp.Tags,
  cp.CreationDate AS PostCreated,
  cp.LastActivityDate AS PostLastActivity,
  cp.Score,
  cp.ViewCount,
  cp.AcceptedAnswerId,
  ce.EditDate,
  ce.EditorId,
  ce.EditComment,
  cv.UpVotes,
  cv.DownVotes,
  cv.CloseVotes,
  h.TagName AS TopTag,
  h.total_posts AS TagPostCount,
  h.avg_user_rep AS TagAvgUserRep
FROM complex_post_stats cp
LEFT JOIN correlated_votes cv ON cp.PostId = cv.PostId
LEFT JOIN latest_edits ce ON ce.PostId = cp.PostId
LEFT JOIN hotness h ON TRUE
LEFT JOIN Users cu ON cp.OwnerUserId = cu.Id
LEFT JOIN recent_users rp ON rp.rn = 1
ORDER BY cp.LastActivityDate DESC
LIMIT 200;