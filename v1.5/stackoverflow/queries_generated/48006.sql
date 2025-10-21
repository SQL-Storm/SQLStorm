-- {"query": "48006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1056} 
WITH
  QuestionScores AS (
    SELECT
      p.Id AS QuestionId,
      p.Score,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount,
      p.CreationDate AS QuestionCreationDate,
      u.Reputation AS OwnerReputation,
      u.UpVotes AS OwnerUpVotes,
      u.DownVotes AS OwnerDownVotes
    FROM
      Posts AS p
      JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 -- Questions
      AND p.Score > 0
      AND p.AnswerCount > 0
      AND p.FavoriteCount > 0
      AND p.ViewCount > 1000
      AND u.Reputation > 10000
  ),
  AnswerMetrics AS (
    SELECT
      ph.PostId AS QuestionId,
      COUNT(DISTINCT ph.Id) AS EditCount,
      AVG(
        CASE
          WHEN ph.PostHistoryTypeId IN (2, 5) THEN -- Edit Body
            CHAR_LENGTH(ph.Text)
          ELSE
            0
        END
      ) AS AvgBodyLength,
      COUNT(
        CASE
          WHEN ph.PostHistoryTypeId = 24 THEN -- Suggested Edit Applied
            1
        END
      ) AS SuggestedEditsApplied
    FROM
      PostHistory AS ph
      JOIN Posts AS p ON ph.PostId = p.Id
    WHERE
      p.PostTypeId = 2 -- Answers
      AND ph.CreationDate >= (
        SELECT
          MIN(QuestionCreationDate)
        FROM
          QuestionScores
      )
    GROUP BY
      ph.PostId
  ),
  CommentStats AS (
    SELECT
      c.PostId AS QuestionId,
      COUNT(DISTINCT c.Id) AS CommentCount,
      AVG(c.Score) AS AvgCommentScore
    FROM
      Comments AS c
      JOIN Posts AS p ON c.PostId = p.Id
    WHERE
      p.PostTypeId = 1 -- Questions
      AND c.CreationDate >= (
        SELECT
          MIN(QuestionCreationDate)
        FROM
          QuestionScores
      )
    GROUP BY
      c.PostId
  ),
  CloseVoteStats AS (
    SELECT
      ph.PostId AS QuestionId,
      COUNT(
        CASE
          WHEN ph.PostHistoryTypeId = 10 THEN -- Post Closed
            1
        END
      ) AS CloseVoteCount,
      AVG(
        CASE
          WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Comment AS INT) -- Assuming Comment stores CloseReasonId as an integer
          ELSE NULL
        END
      ) AS AvgCloseReason
    FROM
      PostHistory AS ph
      JOIN Posts AS p ON ph.PostId = p.Id
    WHERE
      p.PostTypeId = 1 -- Questions
      AND ph.CreationDate >= (
        SELECT
          MIN(QuestionCreationDate)
        FROM
          QuestionScores
      )
      AND ph.PostHistoryTypeId IN (10, 11) -- Post Closed, Post Reopened
    GROUP BY
      ph.PostId
  )
SELECT
  qs.QuestionId,
  qs.Score,
  qs.AnswerCount,
  qs.FavoriteCount,
  qs.ViewCount,
  qs.QuestionCreationDate,
  qs.OwnerReputation,
  qs.OwnerUpVotes,
  qs.OwnerDownVotes,
  COALESCE(am.EditCount, 0) AS TotalEdits,
  COALESCE(am.AvgBodyLength, 0) AS AvgAnswerBodyLength,
  COALESCE(am.SuggestedEditsApplied, 0) AS SuggestedEditsApplied,
  COALESCE(cs.CommentCount, 0) AS TotalComments,
  COALESCE(cs.AvgCommentScore, 0) AS AvgCommentScore,
  COALESCE(cvs.CloseVoteCount, 0) AS TotalCloseVotes,
  COALESCE(cvs.AvgCloseReason, 0) AS AvgCloseReasonType
FROM
  QuestionScores AS qs
LEFT JOIN
  AnswerMetrics AS am
  ON qs.QuestionId = am.QuestionId
LEFT JOIN
  CommentStats AS cs
  ON qs.QuestionId = cs.QuestionId
LEFT JOIN
  CloseVoteStats AS cvs
  ON qs.QuestionId = cvs.QuestionId
WHERE
  qs.QuestionCreationDate >= DATE('now', '-1 year')
ORDER BY
  qs.Score DESC,
  qs.ViewCount DESC
LIMIT 1000;