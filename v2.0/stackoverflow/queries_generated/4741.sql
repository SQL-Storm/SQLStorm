-- {"query": "4741.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1265} 
WITH
  RankedAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 2 -- Answers
  ),
  TopQuestions AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.CreationDate AS QuestionCreationDate,
      q.AnswerCount,
      q.FavoriteCount,
      q.Score AS QuestionScore,
      q.ViewCount AS QuestionViewCount,
      (
        SELECT
          COUNT(*)
        FROM
          PostLinks AS pl
        WHERE
          pl.PostId = q.Id AND pl.LinkTypeId = 3 -- Duplicate links
      ) AS DuplicateLinkCount
    FROM
      Posts AS q
    WHERE
      q.PostTypeId = 1 -- Questions
      AND q.CreationDate >= DATE('now', '-365 day')
      AND q.ClosedDate IS NULL
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      (
        SELECT
          COUNT(DISTINCT ph.PostId)
        FROM
          PostHistory AS ph
        WHERE
          ph.UserId = u.Id
      ) AS PostEdits,
      (
        SELECT
          COUNT(*)
        FROM
          Comments AS c
        WHERE
          c.UserId = u.Id
      ) AS CommentCount,
      (
        SELECT
          COUNT(*)
        FROM
          Votes AS v
        WHERE
          v.UserId = u.Id AND v.VoteTypeId IN (2, 3) -- Upvotes and Downvotes
      ) AS VoteCount
    FROM
      Users AS u
  ),
  QuestionDetails AS (
    SELECT
      tq.QuestionId,
      tq.Title,
      tq.QuestionOwnerUserId,
      tq.QuestionCreationDate,
      tq.AnswerCount,
      tq.FavoriteCount,
      tq.QuestionScore,
      tq.QuestionViewCount,
      tq.DuplicateLinkCount,
      ra.AnswerId AS BestAnswerId,
      ra.OwnerUserId AS BestAnswerOwnerUserId,
      ra.Score AS BestAnswerScore,
      ra.CreationDate AS BestAnswerCreationDate
    FROM
      TopQuestions AS tq
      LEFT JOIN RankedAnswers AS ra ON tq.QuestionId = ra.QuestionId AND ra.rn = 1
  ),
  UserSatisfaction AS (
    SELECT
      qd.QuestionId,
      qd.QuestionOwnerUserId,
      CASE
        WHEN qd.BestAnswerOwnerUserId IS NOT NULL THEN
          CASE
            WHEN qd.QuestionOwnerUserId = qd.BestAnswerOwnerUserId THEN 1.0 -- Accepted their own answer
            ELSE 0.75 -- Accepted another user's answer
          END
        ELSE 0.25 -- No answer accepted
      END AS SatisfactionScore
    FROM
      QuestionDetails AS qd
  )
SELECT
  qd.QuestionId,
  qd.Title,
  qd.QuestionCreationDate,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.AnswerCount,
  qd.FavoriteCount,
  qd.DuplicateLinkCount,
  COALESCE(ua_q.DisplayName, 'Deleted User') AS QuestionOwnerDisplayName,
  COALESCE(ua_a.DisplayName, 'Deleted User') AS BestAnswerOwnerDisplayName,
  ua_q.Reputation AS QuestionOwnerReputation,
  ua_a.Reputation AS BestAnswerOwnerReputation,
  qd.BestAnswerId,
  qd.BestAnswerScore,
  qd.BestAnswerCreationDate,
  (qd.QuestionScore + qd.BestAnswerScore * 0.5) AS WeightedScore,
  us.SatisfactionScore,
  CASE
    WHEN qd.QuestionViewCount > 100000 THEN 'Very Popular'
    WHEN qd.QuestionViewCount > 10000 THEN 'Popular'
    ELSE 'Standard'
  END AS PopularityCategory,
  CASE
    WHEN qd.QuestionOwnerUserId = qd.BestAnswerOwnerUserId THEN 'Self-Accepted'
    WHEN qd.BestAnswerId IS NOT NULL THEN 'Answered'
    ELSE 'Unanswered'
  END AS AnswerStatus,
  ua_q.PostEdits AS QuestionOwnerEdits,
  ua_a.CommentCount AS BestAnswerOwnerComments,
  ua_q.VoteCount AS QuestionOwnerVotes,
  CAST(STRFTIME('%Y-%m', qd.QuestionCreationDate) AS TEXT) AS QuestionMonth
FROM
  QuestionDetails AS qd
  LEFT JOIN UserActivity AS ua_q ON qd.QuestionOwnerUserId = ua_q.UserId
  LEFT JOIN UserActivity AS ua_a ON qd.BestAnswerOwnerUserId = ua_a.UserId
  JOIN UserSatisfaction AS us ON qd.QuestionId = us.QuestionId
WHERE
  qd.QuestionScore > 0
  AND qd.AnswerCount > 0
ORDER BY
  PopularityCategory DESC,
  qd.QuestionScore DESC,
  us.SatisfactionScore DESC,
  qd.QuestionViewCount DESC;