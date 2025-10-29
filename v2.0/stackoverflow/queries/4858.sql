-- {"query": "4858.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 784}
WITH
  RankedQuestions AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      ROW_NUMBER() OVER (
        ORDER BY
          p.Score DESC,
          p.AnswerCount DESC,
          p.CreationDate ASC
      ) AS RankNum,
      CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted' ELSE 'Not Accepted' END AS AcceptanceStatus
    FROM Posts p
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Score > 0
  ),
  UserPostContributions AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgScore
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  HighReputationUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      upc.TotalPosts,
      upc.QuestionCount,
      upc.AnswerCount,
      upc.AvgScore,
      CASE
        WHEN u.LastAccessDate < (cast('2024-10-01' as date) - INTERVAL '1 year') THEN 'Inactive'
        ELSE 'Active'
      END AS UserStatus
    FROM Users u
    JOIN UserPostContributions upc
      ON u.Id = upc.OwnerUserId
    WHERE
      u.Reputation >= 10000
  )
SELECT
  rq.PostId,
  rq.Title,
  rq.RankNum,
  rq.AcceptanceStatus,
  hr.DisplayName AS OwnerDisplayName,
  hr.Reputation AS OwnerReputation,
  hr.UserStatus AS OwnerStatus,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM Comments c
      WHERE
        c.PostId = rq.PostId AND c.UserId IS NOT NULL
    ),
    0
  ) AS CommentCountOnPost,
  (
    SELECT
      COUNT(*)
    FROM PostLinks pl
    WHERE
      pl.PostId = rq.PostId AND pl.LinkTypeId = 3
  ) AS DuplicateLinks
FROM RankedQuestions rq
LEFT JOIN HighReputationUsers hr
  ON rq.OwnerUserId = hr.UserId
WHERE
  rq.RankNum BETWEEN 1 AND 100

UNION ALL

SELECT
  NULL AS PostId,
  '--- Other Metrics ---' AS Title,
  NULL AS RankNum,
  NULL AS AcceptanceStatus,
  NULL AS OwnerDisplayName,
  NULL AS OwnerReputation,
  NULL AS OwnerStatus,
  AVG(CAST(rq.AnswerCount AS DOUBLE PRECISION)) AS CommentCountOnPost,
  SUM(
    CASE
      WHEN EXISTS(
        SELECT 1
        FROM Votes v
        WHERE v.PostId = rq.PostId AND v.VoteTypeId = 2
      ) THEN 1
      ELSE 0
    END
  ) AS DuplicateLinks
FROM RankedQuestions rq
WHERE
  rq.RankNum BETWEEN 101 AND 200

ORDER BY
  RankNum NULLS LAST,
  PostId NULLS LAST;