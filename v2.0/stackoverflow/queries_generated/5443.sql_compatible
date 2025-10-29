WITH RankedPostActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    NULL AS CloseReasonTypes, -- placeholder to ensure proper column resolution in some engines
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        GREATEST(COALESCE(p.LastActivityDate, p.CreationDate), COALESCE(p.CreationDate, DATE '1900-01-01')) DESC,
        p.Score DESC,
        p.ViewCount DESC,
        p.Id ASC
    ) AS rn
  FROM Posts p
  LEFT JOIN (
    SELECT 1 AS dummy
  ) l ON TRUE
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    AND p.ClosedDate IS NULL
),
TopInteractions AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.Title,
    rp.Tags,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    COALESCE(vt.TotalUp, 0) AS UpVotes,
    COALESCE(vt.TotalDown, 0) AS DownVotes,
    COALESCE(vc.TotalComment, 0) AS CommentCount,
    COALESCE(b.TotalBadges, 0) AS BadgeCount
  FROM RankedPostActivity rp
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUp,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDown
    FROM Votes
    GROUP BY PostId
  ) vt ON vt.PostId = rp.PostId
  LEFT JOIN (
    SELECT PostId,
           COUNT(*) AS TotalComment
    FROM Comments
    GROUP BY PostId
  ) vc ON vc.PostId = rp.PostId
  LEFT JOIN (
    SELECT p.Id AS PostId,
           COUNT(b.Name) AS TotalBadges
    FROM Posts p
    LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
    GROUP BY p.Id
  ) b ON b.PostId = rp.PostId
  WHERE rp.rn <= 50
),
WindowedStats AS (
  SELECT
    t.PostId,
    t.PostTypeId,
    t.Title,
    t.Tags,
    t.OwnerUserId,
    t.OwnerDisplayName,
    t.CreationDate,
    t.LastActivityDate,
    t.Score,
    t.ViewCount,
    t.UpVotes,
    t.DownVotes,
    t.CommentCount,
    t.BadgeCount,
    AVG(t.UpVotes) OVER (PARTITION BY t.PostTypeId) AS AvgUpVotesByType,
    SUM(t.DownVotes) OVER (PARTITION BY t.PostTypeId) AS SumDownVotesByType,
    ROW_NUMBER() OVER (PARTITION BY t.PostTypeId ORDER BY t.UpVotes DESC, t.DownVotes ASC) AS rank_by_votes
  FROM TopInteractions t
)
SELECT
  PostId,
  PostTypeId,
  Title,
  Tags,
  OwnerUserId,
  OwnerDisplayName,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  UpVotes,
  DownVotes,
  CommentCount,
  BadgeCount,
  AvgUpVotesByType,
  SumDownVotesByType,
  rank_by_votes
FROM WindowedStats
ORDER BY PostTypeId, rank_by_votes
FETCH FIRST 100 ROWS ONLY;