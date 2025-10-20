SELECT
  p.Id AS PostId,
  p.Title,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.Tags,
  p.OwnerDisplayName AS Owner,
  COALESCE(a.CountAnswers, 0) AS AnswerCount,
  COALESCE(vs.Upvotes, 0) AS Upvotes,
  COALESCE(vs.Downvotes, 0) AS Downvotes,
  COALESCE(bd.CountBadges, 0) AS BadgeCount,
  COALESCE(cc.Comments, 0) AS CommentCount,
  p.LastEditDate,
  p.LastActivityDate,
  u.Reputation
FROM
  Posts p
  LEFT JOIN (
    SELECT ParentId, COUNT(*) AS CountAnswers
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
  ) a ON a.ParentId = p.Id
  LEFT JOIN LATERAL (
    SELECT v.PostId AS PostId, 
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes v
    WHERE v.PostId = p.Id
    GROUP BY v.PostId
  ) vs ON TRUE
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CountBadges
    FROM Badges
    GROUP BY PostId
  ) bd ON bd.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Comments
    FROM Comments
    GROUP BY PostId
  ) cc ON cc.PostId = p.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE
  p.PostTypeId = 1
  AND p.AcceptedAnswerId IS NOT NULL
ORDER BY
  p.CreationDate DESC
FETCH FIRST 100 ROWS ONLY;