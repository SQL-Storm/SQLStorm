-- {"query": "4195.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 861} 

WITH
  HighReputationUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes,
      COUNT(DISTINCT b.Id) AS BadgeCount
    FROM
      Users AS u
    LEFT JOIN
      Badges AS b
      ON u.Id = b.UserId
    WHERE
      u.Reputation > 50000
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes
    HAVING
      COUNT(DISTINCT b.Id) > 10
  ),
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.Score,
      p.AnswerCount,
      p.OwnerUserId,
      p.CreationDate,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNum
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 1 -- Question
      AND p.CreationDate >= DATE('now', '-30 day')
  ),
  QuestionPerformance AS (
    SELECT
      rq.QuestionId,
      rq.Title,
      rq.Score,
      rq.AnswerCount,
      hru.DisplayName AS OwnerDisplayName,
      hru.Reputation AS OwnerReputation,
      (
        CASE
          WHEN rq.AnswerCount > 0 THEN CAST(rq.Score AS REAL) / rq.AnswerCount
          ELSE CAST(rq.Score AS REAL)
        END
      ) AS ScorePerAnswer,
      CASE
        WHEN rq.AnswerCount BETWEEN 0 AND 5 THEN 'Low'
        WHEN rq.AnswerCount BETWEEN 6 AND 20 THEN 'Medium'
        ELSE 'High'
      END AS AnswerBand,
      CASE
        WHEN hru.Reputation IS NULL THEN 'No High Rep User'
        ELSE 'High Rep User'
      END AS OwnerStatus
    FROM
      RecentQuestions AS rq
    LEFT JOIN
      HighReputationUsers AS hru
      ON rq.OwnerUserId = hru.UserId
    WHERE
      rq.RowNum <= 100 -- Top 100 most recent questions
  )
SELECT
  qp.QuestionId,
  qp.Title,
  qp.Score,
  qp.AnswerCount,
  qp.OwnerDisplayName,
  qp.OwnerReputation,
  qp.ScorePerAnswer,
  qp.AnswerBand,
  qp.OwnerStatus,
  (
    SELECT
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) -- Upvotes
    FROM
      Votes AS v
    WHERE
      v.PostId = qp.QuestionId
  ) AS TotalUpvotes,
  (
    SELECT
      COUNT(*)
    FROM
      Comments AS c
    WHERE
      c.PostId = qp.QuestionId
      AND c.CreationDate >= DATE('now', '-7 day')
      AND c.Text LIKE '%interesting%' -- Search for specific keywords in comments
  ) AS RecentInterestingComments,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        PostLinks AS pl
      WHERE
        pl.PostId = qp.QuestionId
        AND pl.LinkTypeId = 3 -- Duplicate link
    ) THEN 'Is Duplicate'
    ELSE 'Not Duplicate'
  END AS DuplicateStatus
FROM
  QuestionPerformance AS qp
WHERE
  qp.ScorePerAnswer > 1.5
  OR qp.AnswerCount > 10
ORDER BY
  qp.Score DESC,
  qp.AnswerCount DESC
LIMIT 50;
