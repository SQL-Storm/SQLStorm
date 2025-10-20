WITH cte AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount AS PostFavoriteCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Posts ap
        WHERE ap.ParentId = p.Id
          AND ap.PostTypeId = 2
          AND ap.Score >= 0
      )
      ELSE 0
    END AS AnswersCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
          AND v.VoteTypeId = 2
      )
      ELSE 0
    END AS UpVotes,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
          AND v.VoteTypeId = 3
      )
      ELSE 0
    END AS DownVotes,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
          AND v.VoteTypeId = 5
      )
      ELSE 0
    END AS VoteFavoriteCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id
          AND v.VoteTypeId IN (6, 7)
      )
      ELSE 0
    END AS CloseVotes,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
          AND ph.PostHistoryTypeId IN (10, 11)
      )
      ELSE 0
    END AS CloseReopenCount,
    CASE
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = p.OwnerUserId
          AND b.Name IN ('Accepted', 'Enlightened', 'Populist', 'Socratic')
      )
      ELSE 0
    END AS OwnerBadgeCount
  FROM Posts p
)
SELECT
  PostId,
  PostTypeId,
  OwnerUserId,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  AnswersCount,
  UpVotes,
  DownVotes,
  PostFavoriteCount,
  VoteFavoriteCount,
  CloseVotes,
  CloseReopenCount,
  OwnerBadgeCount
FROM cte
WHERE PostTypeId = 1
ORDER BY LastActivityDate DESC
LIMIT 100;