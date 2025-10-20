-- {"query": "48019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 518} 
WITH QuestionEdits AS (
  SELECT
    ph.PostId,
    COUNT(DISTINCT ph.RevisionGUID) AS NumberOfEdits,
    MIN(ph.CreationDate) AS FirstEditDate,
    MAX(ph.CreationDate) AS LastEditDate
  FROM PostHistory AS ph
  JOIN Posts AS p
    ON ph.PostId = p.Id
  WHERE
    ph.PostHistoryTypeId IN (4, 5, 6) AND p.PostTypeId = 1
  GROUP BY
    ph.PostId
  HAVING
    COUNT(DISTINCT ph.RevisionGUID) > 2
)
SELECT
  q.Id AS QuestionId,
  u.DisplayName AS OwnerDisplayName,
  q.Title AS QuestionTitle,
  q.CreationDate AS QuestionCreationDate,
  q.Score AS QuestionScore,
  q.ViewCount AS QuestionViewCount,
  qe.NumberOfEdits AS NumberOfEdits,
  qe.FirstEditDate AS FirstEditDate,
  qe.LastEditDate AS LastEditDate,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = q.Id
  ) AS CommentCount,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = q.Id OR pl.RelatedPostId = q.Id
  ) AS LinkCount,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.PostId = q.Id AND v.VoteTypeId = 2
  ) AS UpVoteCount,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.PostId = q.Id AND v.VoteTypeId = 3
  ) AS DownVoteCount
FROM Posts AS q
JOIN Users AS u
  ON q.OwnerUserId = u.Id
JOIN QuestionEdits AS qe
  ON q.Id = qe.PostId
WHERE
  q.PostTypeId = 1 AND q.CreationDate >= '2023-01-01' AND q.ClosedDate IS NULL
ORDER BY
  qe.NumberOfEdits DESC,
  q.Score DESC
LIMIT 100;