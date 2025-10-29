-- {"query": "4706.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1160} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      pht.Name AS EditType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserActivitySummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS TotalPostsCreated,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
      MAX(p.CreationDate) AS LastPostCreationDate,
      AVG(p.Score) AS AveragePostScore,
      SUM(p.CommentCount) AS TotalCommentsOnPosts,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id
      ) AS TotalBadges
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  TopContributors AS (
    SELECT
      uas.UserId,
      uas.DisplayName,
      uas.Reputation,
      uas.TotalPostsCreated,
      uas.TotalQuestions,
      uas.TotalAnswers,
      uas.AveragePostScore,
      uas.TotalBadges,
      ROW_NUMBER() OVER (ORDER BY uas.TotalPostsCreated DESC, uas.Reputation DESC) AS contributor_rank
    FROM UserActivitySummary AS uas
    WHERE
      uas.TotalPostsCreated >= 100
  ),
  HighlyRatedAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.Score AS AnswerScore,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS answer_rank_for_question
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2 -- Answer
      AND p.Score > 5 -- Only consider answers with a score greater than 5
  )
SELECT
  t1.DisplayName AS PostOwnerDisplayName,
  t1.Reputation AS PostOwnerReputation,
  t1.TotalQuestions AS PostOwnerTotalQuestions,
  t1.TotalAnswers AS PostOwnerTotalAnswers,
  t1.AveragePostScore AS PostOwnerAveragePostScore,
  t1.TotalBadges AS PostOwnerTotalBadges,
  p.Title AS QuestionTitle,
  p.Score AS QuestionScore,
  p.ViewCount AS QuestionViewCount,
  p.CreationDate AS QuestionCreationDate,
  p.AnswerCount AS QuestionAnswerCount,
  pra.EditType AS LatestEditType,
  pra.EditDate AS LatestEditDate,
  hra.AnswerId AS TopAnswerId,
  hra.AnswerScore AS TopAnswerScore,
  hra.AnswerCreationDate AS TopAnswerCreationDate,
  t2.DisplayName AS TopAnswerOwnerDisplayName,
  t2.Reputation AS TopAnswerOwnerReputation,
  t2.TotalPostsCreated AS TopAnswerOwnerTotalPostsCreated,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS QuestionStatus,
  COALESCE(p.FavoriteCount, 0) AS QuestionFavoriteCount,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = p.Id AND pl.LinkTypeId = 3 -- Duplicate Link
    ) THEN 'Has Duplicate Link'
    ELSE 'No Duplicate Link'
  END AS DuplicateLinkStatus
FROM Posts AS p
JOIN UserActivitySummary AS t1
  ON p.OwnerUserId = t1.UserId
LEFT JOIN RankedPostEdits AS pra
  ON p.Id = pra.PostId AND pra.rn = 1
LEFT JOIN HighlyRatedAnswers AS hra
  ON p.Id = hra.QuestionId AND hra.answer_rank_for_question = 1
LEFT JOIN UserActivitySummary AS t2
  ON hra.OwnerUserId = t2.UserId
WHERE
  p.PostTypeId = 1 -- Question
  AND p.CreationDate >= '2023-01-01' -- Filter for recent questions
  AND t1.contributor_rank <= 100 -- Focus on top contributors' questions
ORDER BY
  p.Score DESC,
  p.ViewCount DESC
LIMIT 50;
