-- {"query": "4614.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1005} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  LatestEdits AS (
    SELECT
      rpe.PostId,
      rpe.UserId AS LastEditorUserId,
      rpe.CreationDate AS LastEditDate
    FROM RankedPostEdits AS rpe
    WHERE
      rpe.rn = 1
  ),
  UserPostCounts AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserVoteSummary AS (
    SELECT
      v.UserId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Votes AS v
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  )
SELECT
  p.Id AS PostId,
  pt.Name AS PostTypeName,
  p.Title,
  u.DisplayName AS OwnerDisplayName,
  upc.QuestionCount,
  upc.AnswerCount,
  upc.AcceptedAnswerCount,
  le.LastEditDate,
  le.LastEditorUserId,
  lu.DisplayName AS LastEditorDisplayName,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  COALESCE(p.AnswerCount, 0) AS NumberOfAnswers,
  COALESCE(p.CommentCount, 0) AS NumberOfComments,
  COALESCE(p.FavoriteCount, 0) AS NumberOfFavorites,
  CONCAT(
    'User: ',
    u.DisplayName,
    ' (Rep: ',
    u.Reputation,
    ') | Tags: ',
    p.Tags,
    ' | Score: ',
    p.Score
  ) AS PostSummary,
  uvs.TotalUpVotes AS OwnerTotalUpVotes,
  uvs.TotalDownVotes AS OwnerTotalDownVotes,
  CASE
    WHEN p.Id = p.AcceptedAnswerId THEN 'This is the accepted answer'
    WHEN EXISTS (
      SELECT
        1
      FROM Posts AS a
      WHERE
        a.ParentId = p.Id AND a.Id = p.AcceptedAnswerId
    ) THEN 'This question has an accepted answer'
    ELSE 'No accepted answer yet'
  END AS AcceptanceStatus
FROM Posts AS p
LEFT OUTER JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT OUTER JOIN Users AS u
  ON p.OwnerUserId = u.Id
LEFT OUTER JOIN LatestEdits AS le
  ON p.Id = le.PostId
LEFT OUTER JOIN Users AS lu
  ON le.LastEditorUserId = lu.Id
LEFT OUTER JOIN UserPostCounts AS upc
  ON p.OwnerUserId = upc.OwnerUserId
LEFT OUTER JOIN UserVoteSummary AS uvs
  ON p.OwnerUserId = uvs.UserId
WHERE
  p.CreationDate >= '2023-01-01' AND p.Score > 5
  AND (
    p.Title LIKE '%performance%' OR p.Tags LIKE '%performance%'
  )
  AND EXISTS (
    SELECT
      1
    FROM Comments AS c
    WHERE
      c.PostId = p.Id AND c.Text LIKE '%benchmark%'
  )
ORDER BY
  p.LastActivityDate DESC
LIMIT 100;
