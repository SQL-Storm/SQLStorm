-- {"query": "4679.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1050} 
WITH
  RankedAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2 -- Answers
  ),
  QuestionEngagement AS (
    SELECT
      q.Id AS QuestionId,
      q.OwnerUserId AS QuestionOwnerId,
      q.Title AS QuestionTitle,
      q.CreationDate AS QuestionCreationDate,
      q.Score AS QuestionScore,
      q.ViewCount AS QuestionViewCount,
      q.FavoriteCount AS QuestionFavoriteCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      MAX(q_edit.CreationDate) AS LastQuestionEditDate,
      MAX(ans.AnswerId) AS BestAnswerId,
      MAX(ans.Score) AS BestAnswerScore,
      MAX(ans.OwnerUserId) AS BestAnswerOwnerId
    FROM Posts AS q
    LEFT JOIN Comments AS c
      ON q.Id = c.PostId
    LEFT JOIN Votes AS v
      ON q.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN PostHistory AS q_edit
      ON q.Id = q_edit.PostId AND q_edit.PostHistoryTypeId IN (4, 5) -- Edit Title, Edit Body
    LEFT JOIN RankedAnswers AS ans
      ON q.Id = ans.QuestionId AND ans.rn = 1
    WHERE
      q.PostTypeId = 1 -- Questions
    GROUP BY
      q.Id,
      q.OwnerUserId,
      q.Title,
      q.CreationDate,
      q.Score,
      q.ViewCount,
      q.FavoriteCount
  )
SELECT
  u.DisplayName AS UserDisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  COUNT(DISTINCT qe.QuestionId) AS QuestionsAsked,
  SUM(qe.QuestionScore) AS TotalQuestionScore,
  AVG(qe.QuestionViewCount) AS AvgQuestionViews,
  COUNT(DISTINCT qe.BestAnswerId) AS AnswersToTheirQuestions,
  SUM(CASE WHEN qe.BestAnswerScore IS NOT NULL THEN qe.BestAnswerScore ELSE 0 END) AS ScoreOfBestAnswersToThem,
  COUNT(DISTINCT CASE WHEN qe.QuestionOwnerId = u.Id THEN 1 ELSE NULL END) AS QuestionsOwnedByThisUser,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = u.Id AND b.Class = 1
  ) AS GoldBadges,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = u.Id AND b.Class = 2
  ) AS SilverBadges,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = u.Id AND b.Class = 3
  ) AS BronzeBadges,
  MAX(qe.LastQuestionEditDate) AS LastQuestionEditedDate,
  SUM(qe.UpVoteCount) AS TotalUpvotesReceivedOnQuestions,
  SUM(qe.DownVoteCount) AS TotalDownvotesReceivedOnQuestions,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'StackOverflowRelated'
    ELSE 'ExternalWebsite'
  END AS WebsiteCategory,
  COUNT(DISTINCT CASE WHEN qe.QuestionCreationDate < u.CreationDate THEN qe.QuestionId ELSE NULL END) AS QuestionsCreatedBeforeUser
FROM Users AS u
LEFT JOIN QuestionEngagement AS qe
  ON u.Id = qe.QuestionOwnerId
WHERE
  u.Id > 0 -- Exclude potential system users
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.WebsiteUrl
HAVING
  COUNT(qe.QuestionId) > 5 -- Only consider users with at least 5 questions
ORDER BY
  u.Reputation DESC,
  QuestionsAsked DESC
LIMIT 100;