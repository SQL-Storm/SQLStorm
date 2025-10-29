-- {"query": "4996.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1234}
WITH
  HighReputationUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) AS rn
    FROM
      Users AS u
    WHERE
      u.Reputation > 10000
  ),
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount AS QuestionAnswerCount,
      p.FavoriteCount AS QuestionFavoriteCount,
      p.OwnerUserId AS QuestionOwnerUserId,
      pt.Name AS QuestionTypeName
    FROM
      Posts AS p
      JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    WHERE
      p.PostTypeId = 1 -- Question
      AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
  ),
  TopAnswers AS (
    SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.Score AS AnswerScore,
      a.OwnerUserId AS AnswerOwnerUserId,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
    FROM
      Posts AS a
    WHERE
      a.PostTypeId = 2 -- Answer
      AND a.Score > 0
  ),
  QuestionMetrics AS (
    SELECT
      rq.QuestionId,
      rq.QuestionTitle,
      rq.QuestionCreationDate,
      rq.QuestionScore,
      rq.QuestionViewCount,
      rq.QuestionAnswerCount,
      rq.QuestionFavoriteCount,
      rq.QuestionOwnerUserId,
      hr.DisplayName AS OwnerDisplayName,
      hr.Reputation AS OwnerReputation,
      CASE
        WHEN rq.QuestionScore > 100 THEN 'High'
        WHEN rq.QuestionScore BETWEEN 10 AND 100 THEN 'Medium'
        ELSE 'Low'
      END AS ScoreCategory,
      LENGTH(rq.QuestionTitle) AS TitleLength,
      CASE
        WHEN POSITION('?' IN rq.QuestionTitle) > 0 THEN 'Yes'
        ELSE 'No'
      END AS HasQuestionMark,
      hr.rn AS OwnerRank
    FROM
      RecentQuestions AS rq
      LEFT JOIN HighReputationUsers AS hr ON rq.QuestionOwnerUserId = hr.UserId
    WHERE
      hr.rn <= 5 -- Consider top 5 most reputable users as owners
  ),
  AnswerMetrics AS (
    SELECT
      ta.QuestionId,
      ta.AnswerId,
      ta.AnswerScore,
      ta.AnswerOwnerUserId,
      ta2.AnswerScore AS SecondBestAnswerScore,
      ta.AnswerScore - ta2.AnswerScore AS ScoreDifference,
      CASE
        WHEN ta.AnswerScore = ta2.AnswerScore THEN 1
        ELSE 0
      END AS TieForBestAnswer
    FROM
      TopAnswers AS ta
      LEFT JOIN TopAnswers AS ta2 ON ta.QuestionId = ta2.QuestionId AND ta2.rn = 2
    WHERE
      ta.rn = 1 -- Only consider the top answer for each question
  )
SELECT
  qm.QuestionId,
  qm.QuestionTitle,
  qm.QuestionCreationDate,
  qm.QuestionScore,
  qm.QuestionViewCount,
  qm.QuestionFavoriteCount,
  qm.OwnerDisplayName,
  qm.OwnerReputation,
  qm.ScoreCategory,
  qm.HasQuestionMark,
  am.AnswerId,
  am.AnswerScore,
  am.AnswerOwnerUserId,
  am.ScoreDifference,
  am.TieForBestAnswer,
  (UPPER(SUBSTRING(qm.QuestionTitle FROM 1 FOR 3)) || '-' || LOWER(SUBSTRING(qm.QuestionTitle FROM CHAR_LENGTH(qm.QuestionTitle)-2 FOR 3))) AS TitleAbbreviation,
  COALESCE(am.AnswerScore, 0) AS NonNullAnswerScore,
  CASE
    WHEN am.AnswerScore IS NULL THEN 'No Answers'
    WHEN am.ScoreDifference > 50 THEN 'Significant Lead'
    WHEN am.ScoreDifference BETWEEN 10 AND 50 THEN 'Moderate Lead'
    ELSE 'Close'
  END AS AnswerLeadStatus,
  CASE
    WHEN qm.OwnerReputation IS NULL THEN 'Unknown'
    WHEN qm.OwnerReputation > 50000 THEN 'Expert'
    WHEN qm.OwnerReputation > 20000 THEN 'Senior'
    ELSE 'Intermediate'
  END AS OwnerExperienceLevel
FROM
  QuestionMetrics AS qm
FULL OUTER JOIN
  AnswerMetrics AS am ON qm.QuestionId = am.QuestionId
WHERE
  (am.AnswerScore IS NULL OR am.AnswerScore > qm.QuestionScore * 0.1) -- Answers with at least 10% of question score
  AND qm.QuestionViewCount > 50 -- Questions with more than 50 views
ORDER BY
  qm.QuestionCreationDate DESC,
  qm.QuestionScore DESC,
  am.AnswerScore DESC
LIMIT 100;