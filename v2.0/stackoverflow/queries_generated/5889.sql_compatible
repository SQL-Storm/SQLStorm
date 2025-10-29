WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
),
heritage AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.LastActivityDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COALESCE(b.Class, 0) AS BadgeClass,
    b.Date AS BadgeDate
  FROM recent_questions q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  LEFT JOIN Badges b ON u.Id = b.UserId
      AND b.Date = (
        SELECT MAX(Date) FROM Badges WHERE UserId = u.Id
      )
),
linked AS (
  SELECT
    h.PostId,
    h.Title,
    h.Tags,
    h.Score,
    h.ViewCount,
    h.OwnerUserId,
    h.OwnerDisplayName,
    h.Reputation,
    h.BadgeClass,
    h.BadgeDate,
    v1.VoteTypeId AS RecentVoteTypeId,
    v1.CreationDate AS VoteDate,
    vl.BountyAmount AS RecentBounty,
    v1.BountyAmount AS RecentVoteBounty,
    v1.Id AS RecentVoteId
  FROM heritage h
  LEFT JOIN Votes v1 ON h.PostId = v1.PostId
    AND v1.CreationDate = (
      SELECT MAX(CreationDate)
      FROM Votes
      WHERE PostId = h.PostId
    )
  LEFT JOIN Votes vl ON h.PostId = vl.PostId
    AND vl.VoteTypeId = 8 -- BountyStart
    AND vl.CreationDate = (
      SELECT MAX(CreationDate)
      FROM Votes
      WHERE PostId = h.PostId AND VoteTypeId = 8
    )
),
stats AS (
  SELECT
    l.PostId,
    l.Title,
    l.Tags,
    l.Score,
    l.ViewCount,
    l.OwnerDisplayName,
    l.Reputation,
    l.BadgeClass,
    l.BadgeDate,
    l.RecentVoteTypeId,
    l.VoteDate,
    l.RecentBounty,
    OC.ClosedReason,
    OC.ClosedDate,
    l.RecentVoteId
  FROM linked l
  LEFT JOIN PostHistory ph ON ph.PostId = l.PostId
    AND ph.PostHistoryTypeId = 10 -- Post Closed
    AND ph.CreationDate = (
      SELECT MAX(pc.CreationDate)
      FROM PostHistory pc
      WHERE pc.PostId = l.PostId AND pc.PostHistoryTypeId = 10
    )
  LEFT JOIN (
    SELECT ph.PostId, ph.Comment AS ClosedReason, ph.CreationDate AS ClosedDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
  ) OC ON OC.PostId = l.PostId
)
SELECT
  s.PostId,
  s.Title,
  s.Tags,
  s.Score,
  s.ViewCount,
  s.OwnerDisplayName,
  s.Reputation,
  s.BadgeClass,
  s.BadgeDate,
  s.RecentVoteTypeId AS RecentVoteType,
  s.VoteDate,
  s.RecentBounty,
  s.ClosedReason,
  s.ClosedDate,
  STRING_AGG(DISTINCT t.TagName, ',') FILTER (WHERE t.TagName IS NOT NULL) AS TagList,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = s.PostId) AS CommentCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = s.PostId AND v.VoteTypeId = 2) AS UpModCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = s.PostId AND v.VoteTypeId = 3) AS DownModCount
FROM stats s
LEFT JOIN Tags t ON t.WikiPostId = s.PostId OR t.ExcerptPostId = s.PostId
GROUP BY
  s.PostId, s.Title, s.Tags, s.Score, s.ViewCount, s.OwnerDisplayName, s.Reputation,
  s.BadgeClass, s.BadgeDate, s.RecentVoteTypeId, s.VoteDate, s.RecentBounty,
  s.ClosedReason, s.ClosedDate
ORDER BY s.PostId DESC
LIMIT 100;