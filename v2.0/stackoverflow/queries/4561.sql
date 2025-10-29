-- {"query": "4561.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1535}
WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId AS AnswererUserId,
      p.Score AS AnswerScore,
      p.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 2
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title AS QuestionTitle,
      q.Tags AS QuestionTags,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.CreationDate AS QuestionCreationDate,
      q.Score AS QuestionScore,
      q.AnswerCount,
      q.FavoriteCount,
      q.ClosedDate,
      (
        SELECT COUNT(ph.Id)
        FROM PostHistory ph
        WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId = 10
      ) AS CloseVoteCount,
      (
        SELECT COUNT(ph.Id)
        FROM PostHistory ph
        WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId = 19
      ) AS ProtectionCount
    FROM Posts q
    WHERE q.PostTypeId = 1
  ),
  TopAnswer AS (
    SELECT
      ra.QuestionId,
      ra.PostId AS TopAnswerId,
      ra.AnswererUserId,
      ra.AnswerScore AS TopAnswerScore,
      ra.AnswerCreationDate AS TopAnswerCreationDate,
      u.DisplayName AS TopAnswererDisplayName,
      u.Reputation AS TopAnswererReputation
    FROM RankedAnswers ra
    JOIN Users u
      ON ra.AnswererUserId = u.Id
    WHERE ra.rn = 1
  ),
  QuestionWithBestAnswer AS (
    SELECT
      qd.QuestionId,
      qd.QuestionTitle,
      qd.QuestionTags,
      qd.QuestionOwnerUserId,
      qd.QuestionCreationDate,
      qd.QuestionScore,
      qd.AnswerCount,
      qd.FavoriteCount,
      qd.ClosedDate,
      qd.CloseVoteCount,
      qd.ProtectionCount,
      ta.TopAnswerId,
      ta.AnswererUserId AS BestAnswererUserId,
      ta.TopAnswerScore,
      ta.TopAnswerCreationDate,
      ta.TopAnswererDisplayName,
      ta.TopAnswererReputation,
      CASE
        WHEN qd.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN qd.FavoriteCount > (
          SELECT AVG(FavoriteCount)
          FROM Posts
          WHERE PostTypeId = 1 AND CreationDate BETWEEN qd.QuestionCreationDate - INTERVAL '30' DAY AND qd.QuestionCreationDate + INTERVAL '30' DAY
        ) THEN 'Highly Favorited'
        WHEN ta.TopAnswerScore > (
          SELECT AVG(Score)
          FROM Posts
          WHERE PostTypeId = 2 AND ParentId = qd.QuestionId
        ) * 2 THEN 'Exceptional Answer'
        ELSE 'Standard'
      END AS QuestionCategory
    FROM QuestionDetails qd
    LEFT JOIN TopAnswer ta
      ON qd.QuestionId = ta.QuestionId
  )
SELECT
  qwba.QuestionId,
  qwba.QuestionTitle,
  qwba.QuestionTags,
  qwba.QuestionOwnerUserId,
  qwba.QuestionCreationDate,
  qwba.QuestionScore,
  qwba.AnswerCount,
  qwba.FavoriteCount,
  qwba.ClosedDate,
  qwba.CloseVoteCount,
  qwba.ProtectionCount,
  qwba.QuestionCategory,
  qwba.TopAnswerId,
  qwba.TopAnswerScore,
  qwba.TopAnswerCreationDate,
  qwba.TopAnswererDisplayName,
  qwba.TopAnswererReputation,
  (
    SELECT COUNT(c.Id)
    FROM Comments c
    WHERE c.PostId = qwba.QuestionId
  ) AS CommentCountOnQuestion,
  (
    SELECT SUM(
      CASE
        WHEN pht.Comment ~ '^[+-]?[0-9]*\.?[0-9]+$' THEN CAST(pht.Comment AS NUMERIC)
        WHEN pht.Comment ~ '^[0-9]+$' THEN CAST(pht.Comment AS NUMERIC)
        ELSE 0
      END
    )
    FROM PostHistory pht
    WHERE pht.PostId = qwba.QuestionId AND pht.PostHistoryTypeId = 50
  ) AS CommunityBumpScore,
  CASE
    WHEN qwba.QuestionOwnerUserId IS NULL THEN 'Unknown Owner'
    WHEN qwba.QuestionOwnerUserId = -1 THEN 'Community User'
    ELSE (
      SELECT u2.DisplayName
      FROM Users u2
      WHERE u2.Id = qwba.QuestionOwnerUserId
      FETCH FIRST 1 ROWS ONLY
    )
  END AS QuestionOwnerDisplayName,
  COALESCE(
    (
      SELECT COUNT(*)
      FROM PostLinks pl
      WHERE pl.PostId = qwba.QuestionId AND pl.LinkTypeId = 3
    ),
    0
  ) AS DuplicateLinkCount,
  '---' AS Separator,
  CASE
    WHEN qwba.TopAnswererReputation > 10000 THEN 'High Reputation Answerer'
    WHEN qwba.TopAnswererReputation < 500 THEN 'Low Reputation Answerer'
    ELSE 'Medium Reputation Answerer'
  END AS AnswererReputationLevel,
  UPPER(SUBSTRING(qwba.QuestionTitle FROM 1 FOR 10)) AS FirstTenCharsOfTitle,
  EXTRACT(YEAR FROM qwba.QuestionCreationDate) AS QuestionYear,
  CASE
    WHEN qwba.TopAnswerId IS NULL THEN 'No Accepted Answer'
    WHEN qwba.TopAnswerScore <= 0 THEN 'Zero or Negative Score Answer'
    ELSE 'Positive Score Answer'
  END AS AnswerQuality
FROM QuestionWithBestAnswer qwba
WHERE
  qwba.QuestionScore > 0
  AND qwba.AnswerCount > 0
  AND qwba.QuestionCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
  AND qwba.QuestionTags LIKE '%<sql>%'
UNION
SELECT
  NULL AS QuestionId,
  NULL AS QuestionTitle,
  NULL AS QuestionTags,
  NULL AS QuestionOwnerUserId,
  NULL AS QuestionCreationDate,
  NULL AS QuestionScore,
  NULL AS AnswerCount,
  NULL AS FavoriteCount,
  NULL AS ClosedDate,
  NULL AS CloseVoteCount,
  NULL AS ProtectionCount,
  NULL AS QuestionCategory,
  NULL AS TopAnswerId,
  NULL AS TopAnswerScore,
  NULL AS TopAnswerCreationDate,
  NULL AS TopAnswererDisplayName,
  NULL AS TopAnswererReputation,
  NULL AS CommentCountOnQuestion,
  NULL AS CommunityBumpScore,
  NULL AS QuestionOwnerDisplayName,
  NULL AS DuplicateLinkCount,
  NULL AS Separator,
  NULL AS AnswererReputationLevel,
  NULL AS FirstTenCharsOfTitle,
  NULL AS QuestionYear,
  NULL AS AnswerQuality
FROM Users u
WHERE u.Id NOT IN (
  SELECT OwnerUserId
  FROM Posts
  WHERE PostTypeId = 1
)
FETCH FIRST 1 ROWS ONLY;