-- {"query": "4407.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1261} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      pht.Name AS PostHistoryTypeName,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) /* Edit Title, Edit Body, Edit Tags */
  ),
  UserContributionSummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS QuestionsCount,
      COUNT(DISTINCT a.Id) AS AnswersCount,
      SUM(CASE WHEN c.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
      AVG(p.ViewCount) AS AvgQuestionViews,
      MAX(u.Reputation) AS MaxUserReputation
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1 /* Questions */
    LEFT JOIN Posts AS a
      ON u.Id = a.OwnerUserId AND a.PostTypeId = 2 /* Answers */
    LEFT JOIN Votes AS c
      ON u.Id = c.UserId AND c.VoteTypeId = 2 /* Upvotes */
    WHERE
      u.Views > 1000 AND u.DownVotes < 10
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  HighImpactQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.CreationDate AS QuestionCreationDate,
      p.AnswerCount,
      p.FavoriteCount,
      COUNT(DISTINCT c.Id) AS CommentCountOnQuestion,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCountOnQuestion,
      ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC, p.AnswerCount DESC, p.ViewCount DESC) AS QuestionRank
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 1 /* Questions */ AND p.CreationDate > '2020-01-01'
    GROUP BY
      p.Id,
      p.Title,
      p.CreationDate,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount
    HAVING
      COUNT(DISTINCT c.Id) > 5 AND SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 20
  )
SELECT
  U.DisplayName AS UserDisplayName,
  U.Reputation,
  U.CreationDate AS UserCreationDate,
  UCS.QuestionsCount,
  UCS.AnswersCount,
  UCS.TotalUpvotesReceived,
  UCS.AvgQuestionViews,
  COALESCE(RPE.PostHistoryTypeName, 'No Edits') AS LastEditType,
  RPE.CreationDate AS LastEditDate,
  CASE
    WHEN U.WebsiteUrl IS NOT NULL AND LENGTH(U.WebsiteUrl) > 5 THEN 'Has Website'
    WHEN U.Location IS NOT NULL AND LENGTH(U.Location) > 10 THEN 'Has Location'
    ELSE 'Minimal Profile Info'
  END AS ProfileCompletenessIndicator,
  HIQ.Title AS HighImpactQuestionTitle,
  HIQ.QuestionRank,
  CASE
    WHEN HIQ.QuestionRank <= 10 THEN 'Top 10 Impactful'
    WHEN HIQ.QuestionRank <= 50 THEN 'Top 50 Impactful'
    ELSE 'Other Impactful'
  END AS ImpactLevel,
  CONCAT(
    'User ',
    U.DisplayName,
    ' (',
    U.Id,
    ') has ',
    UCS.QuestionsCount,
    ' questions and ',
    UCS.AnswersCount,
    ' answers.'
  ) AS UserSummaryString,
  ABS(U.UpVotes - U.DownVotes) AS NetVotesCasted,
  U.Views AS UserTotalViews,
  HIQ.AnswerCount AS HighImpactQuestionAnswers,
  HIQ.FavoriteCount AS HighImpactQuestionFavorites,
  U.DisplayName LIKE '%Admin%' AS IsLikelyAdmin
FROM Users AS U
JOIN UserContributionSummary AS UCS
  ON U.Id = UCS.UserId
LEFT JOIN RankedPostEdits AS RPE
  ON U.Id = RPE.UserId AND RPE.rn = 1
LEFT JOIN HighImpactQuestions AS HIQ
  ON U.Id = (
    SELECT
      OwnerUserId
    FROM Posts
    WHERE
      Id = (
        SELECT
          PostId
        FROM PostLinks
        WHERE
          RelatedPostId = HIQ.QuestionId AND LinkTypeId = 3
      )
  )
WHERE
  UCS.QuestionsCount > 50 OR UCS.AnswersCount > 100
  AND U.Reputation > 5000
  AND (
    RPE.PostHistoryTypeName IS NOT NULL OR U.WebsiteUrl IS NOT NULL
  )
ORDER BY
  U.Reputation DESC,
  HIQ.QuestionRank ASC
LIMIT 100;
