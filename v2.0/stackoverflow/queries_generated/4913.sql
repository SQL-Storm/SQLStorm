-- {"query": "4913.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 841} 

WITH
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      (
        SELECT
          COUNT(DISTINCT ph.PostId)
        FROM
          PostHistory AS ph
        WHERE
          ph.UserId = u.Id
          AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edits
      ) AS EditCount
    FROM
      Users AS u
    WHERE
      u.Reputation > 10000
  ),
  PostsWithCommunity AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
      pt.Name AS PostTypeName
    FROM
      Posts AS p
      JOIN PostTypes AS pt
        ON p.PostTypeId = pt.Id
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers
  ),
  UserPostStats AS (
    SELECT
      pu.OwnerUserId,
      COUNT(pu.PostId) AS TotalPosts,
      SUM(pu.Score) AS TotalScore,
      AVG(CAST(pu.FavoriteCount AS FLOAT)) AS AvgFavoriteCount,
      MAX(pu.CreationDate) AS LastPostDate
    FROM
      PostsWithCommunity AS pu
    WHERE
      pu.OwnerUserId IS NOT NULL
    GROUP BY
      pu.OwnerUserId
  ),
  RankedAnswers AS (
    SELECT
      p.ParentId,
      p.Id AS AnswerId,
      p.Score AS AnswerScore,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS Rank
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 2 -- Answers
  )
SELECT
  hr.DisplayName,
  hr.Reputation,
  hr.EditCount,
  ups.TotalPosts,
  ups.TotalScore,
  ups.AvgFavoriteCount,
  ups.LastPostDate,
  COUNT(DISTINCT pwc.PostId) AS TotalQuestions,
  SUM(CASE WHEN pwc.IsCommunityOwned = 1 THEN 1 ELSE 0 END) AS CommunityOwnedQuestions,
  AVG(pwc.Score) AS AvgQuestionScore,
  SUM(CASE WHEN ra.Rank = 1 THEN 1 ELSE 0 END) AS QuestionsWithTopAnswer,
  SUM(CASE WHEN pwc.AnswerCount > 0 AND pwc.FavoriteCount > pwc.AnswerCount * 2 THEN 1 ELSE 0 END) AS HighlyFavoritedQuestions
FROM
  HighReputationUsers AS hr
LEFT OUTER JOIN
  Users AS u
  ON hr.Id = u.Id
LEFT OUTER JOIN
  UserPostStats AS ups
  ON hr.Id = ups.OwnerUserId
LEFT OUTER JOIN
  PostsWithCommunity AS pwc
  ON hr.Id = pwc.OwnerUserId
LEFT OUTER JOIN
  RankedAnswers AS ra
  ON pwc.PostId = ra.ParentId
GROUP BY
  hr.DisplayName,
  hr.Reputation,
  hr.EditCount,
  ups.TotalPosts,
  ups.TotalScore,
  ups.AvgFavoriteCount,
  ups.LastPostDate
HAVING
  COUNT(pwc.PostId) > 5 -- Only include users with more than 5 posts
ORDER BY
  hr.Reputation DESC,
  ups.TotalScore DESC;
