-- {"query": "4790.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1389} 
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      u.DisplayName AS EditorDisplayName,
      ph.CreationDate AS EditDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    JOIN Users AS u
      ON ph.UserId = u.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 7, 8) -- Edit Title, Edit Body, Rollback Title, Rollback Body
  ),
  RecentPostScores AS (
    SELECT
      p.Id AS PostId,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate AS PostCreationDate,
      u.DisplayName AS OwnerDisplayName,
      pt.Name AS PostTypeName,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
      END AS PostStatus,
      ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS ActivityRank
    FROM Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.Score > 50 -- Focusing on posts with significant engagement
  )
SELECT
  rps.PostId,
  rps.PostTypeName,
  rps.OwnerDisplayName,
  rps.PostCreationDate,
  rps.Score,
  rps.AnswerCount,
  rps.CommentCount,
  rps.FavoriteCount,
  rps.PostStatus,
  rpe.EditDate AS LastEditOrRollbackDate,
  rpe.EditorDisplayName,
  COALESCE(v.VoteCount, 0) AS TotalUpVotes,
  COALESCE(CASE WHEN rp.LinkTypeId = 3 THEN 'Duplicate' ELSE 'Linked' END, 'None') AS LinkType,
  COALESCE(rps.ActivityRank, 999999) AS OverallActivityRank
FROM RecentPostScores AS rps
LEFT JOIN RankedPostEdits AS rpe
  ON rps.PostId = rpe.PostId AND rpe.rn = 1
LEFT JOIN (
  SELECT
    PostId,
    COUNT(*) AS VoteCount
  FROM Votes
  WHERE
    VoteTypeId = 2 -- UpMod
  GROUP BY
    PostId
) AS v
  ON rps.PostId = v.PostId
LEFT JOIN (
  SELECT DISTINCT
    PostId,
    LinkTypeId
  FROM PostLinks
  WHERE
    LinkTypeId = 3 -- Duplicate
) AS rp
  ON rps.PostId = rp.PostId
WHERE
  rps.Score > (
    SELECT
      AVG(Score)
    FROM Posts
    WHERE
      PostTypeId = 1 -- Questions only
  )
  AND EXISTS (
    SELECT
      1
    FROM Comments AS c
    WHERE
      c.PostId = rps.PostId AND LENGTH(c.Text) > 200
  )
GROUP BY
  rps.PostId,
  rps.PostTypeName,
  rps.OwnerDisplayName,
  rps.PostCreationDate,
  rps.Score,
  rps.AnswerCount,
  rps.CommentCount,
  rps.FavoriteCount,
  rps.PostStatus,
  rpe.EditDate,
  rpe.EditorDisplayName,
  v.VoteCount,
  LinkType,
  rps.ActivityRank
HAVING
  SUM(rps.Score) > 1000
UNION
SELECT
  rps.PostId,
  rps.PostTypeName,
  rps.OwnerDisplayName,
  rps.PostCreationDate,
  rps.Score,
  rps.AnswerCount,
  rps.CommentCount,
  rps.FavoriteCount,
  rps.PostStatus,
  rpe.EditDate AS LastEditOrRollbackDate,
  rpe.EditorDisplayName,
  COALESCE(v.VoteCount, 0) AS TotalUpVotes,
  COALESCE(CASE WHEN rp.LinkTypeId = 3 THEN 'Duplicate' ELSE 'Linked' END, 'None') AS LinkType,
  COALESCE(rps.ActivityRank, 999999) AS OverallActivityRank
FROM RecentPostScores AS rps
LEFT JOIN RankedPostEdits AS rpe
  ON rps.PostId = rpe.PostId AND rpe.rn = 1
LEFT JOIN (
  SELECT
    PostId,
    COUNT(*) AS VoteCount
  FROM Votes
  WHERE
    VoteTypeId = 2 -- UpMod
  GROUP BY
    PostId
) AS v
  ON rps.PostId = v.PostId
LEFT JOIN (
  SELECT DISTINCT
    PostId,
    LinkTypeId
  FROM PostLinks
  WHERE
    LinkTypeId = 1 -- Linked
) AS rp
  ON rps.PostId = rp.PostId
WHERE
  rps.Score < (
    SELECT
      AVG(Score)
    FROM Posts
    WHERE
      PostTypeId = 2 -- Answers only
  )
  AND EXISTS (
    SELECT
      1
    FROM PostHistory AS ph
    WHERE
      ph.PostId = rps.PostId AND ph.PostHistoryTypeId = 2 -- Initial Body
  )
GROUP BY
  rps.PostId,
  rps.PostTypeName,
  rps.OwnerDisplayName,
  rps.PostCreationDate,
  rps.Score,
  rps.AnswerCount,
  rps.CommentCount,
  rps.FavoriteCount,
  rps.PostStatus,
  rpe.EditDate,
  rpe.EditorDisplayName,
  v.VoteCount,
  LinkType,
  rps.ActivityRank
HAVING
  COUNT(rps.PostId) > 5
ORDER BY
  OverallActivityRank
LIMIT 50;