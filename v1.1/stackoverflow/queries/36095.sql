SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.OwnerUserId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.CommentCount,
  p.AnswerCount,
  p.Tags,
  p.LastActivityDate,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.Location,
  u.AboutMe,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  (SELECT AVG(p2.ViewCount) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId) AS AvgPostViewsByOwner,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountOnPost,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicatesCount,
  (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = p.Id) AS TotalVotesOnPost,
  (CASE WHEN COUNT(*) FILTER (WHERE v.VoteTypeId = 2) = 0 THEN 0.0
        ELSE CAST(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS NUMERIC) /
             NULLIF(COUNT(*) FILTER (WHERE p.OwnerUserId = p.OwnerUserId),0)
   END) AS AvgUpVotesPerPostByOwner
FROM
  Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
WHERE
  p.PostTypeId IN (1, 2)
  AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365' DAY
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.OwnerUserId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.CommentCount,
  p.AnswerCount,
  p.Tags,
  p.LastActivityDate,
  u.Reputation,
  u.CreationDate,
  u.Location,
  u.AboutMe
ORDER BY
  p.Score DESC,
  p.ViewCount DESC
LIMIT 100;