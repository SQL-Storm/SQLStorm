-- {"query": "4058.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1540} 

WITH
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgScore,
      MAX(p.CreationDate) AS LastPostDate,
      SUM(p.ViewCount) AS TotalViewCount,
      SUM(p.FavoriteCount) AS TotalFavoriteCount
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentStats AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS TotalComments,
      AVG(c.Score) AS AvgCommentScore
    FROM
      Comments AS c
    WHERE
      c.UserId IS NOT NULL
      AND c.UserId <> -1
    GROUP BY
      c.UserId
  ),
  UserVoteStats AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
      COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesGiven
    FROM
      Votes AS v
    WHERE
      v.UserId IS NOT NULL
      AND v.UserId <> -1
    GROUP BY
      v.UserId
  ),
  RecentPostHistory AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserPostContribution AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COALESCE(ups.TotalPosts, 0) AS TotalPosts,
      COALESCE(ups.QuestionCount, 0) AS QuestionCount,
      COALESCE(ups.AnswerCount, 0) AS AnswerCount,
      COALESCE(ups.AvgScore, 0) AS AvgPostScore,
      COALESCE(ucs.TotalComments, 0) AS TotalComments,
      COALESCE(ucs.AvgCommentScore, 0) AS AvgCommentScore,
      COALESCE(uvs.UpVotesGiven, 0) AS UpVotesGiven,
      COALESCE(uvs.DownVotesGiven, 0) AS DownVotesGiven,
      COALESCE(uvs.FavoritesGiven, 0) AS FavoritesGiven,
      ups.LastPostDate,
      ups.TotalViewCount,
      ups.TotalFavoriteCount,
      (
        SELECT
          COUNT(ph.PostId)
        FROM
          RecentPostHistory AS ph
        WHERE
          ph.UserId = u.Id AND ph.rn = 1
      ) AS RecentEdits
    FROM
      Users AS u
      LEFT JOIN UserPostStats AS ups ON u.Id = ups.OwnerUserId
      LEFT JOIN UserCommentStats AS ucs ON u.Id = ucs.UserId
      LEFT JOIN UserVoteStats AS uvs ON u.Id = uvs.UserId
  ),
  PostWithMaxScore AS (
    SELECT
      Id,
      PostTypeId,
      OwnerUserId,
      Title,
      Score,
      ROW_NUMBER() OVER (PARTITION BY PostTypeId ORDER BY Score DESC) AS score_rank
    FROM
      Posts
    WHERE
      Score IS NOT NULL
  ),
  HighScoringQuestions AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      Score
    FROM
      PostWithMaxScore
    WHERE
      PostTypeId = 1 AND score_rank <= 10
  ),
  HighScoringAnswers AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      Score
    FROM
      PostWithMaxScore
    WHERE
      PostTypeId = 2 AND score_rank <= 10
  )
SELECT
  upc.UserId,
  upc.DisplayName,
  upc.Reputation,
  upc.TotalPosts,
  upc.QuestionCount,
  upc.AnswerCount,
  upc.AvgPostScore,
  upc.TotalComments,
  upc.AvgCommentScore,
  upc.UpVotesGiven,
  upc.DownVotesGiven,
  upc.FavoritesGiven,
  upc.RecentEdits,
  hsq.Title AS TopQuestionTitle,
  hsq.Score AS TopQuestionScore,
  CONCAT(
    'User has ',
    upc.TotalPosts,
    ' posts, ',
    upc.TotalComments,
    ' comments, and their reputation is ',
    upc.Reputation
  ) AS UserSummary,
  CASE
    WHEN upc.AvgPostScore > 50 THEN 'Excellent Contributor'
    WHEN upc.AvgPostScore > 10 THEN 'Good Contributor'
    ELSE 'Standard Contributor'
  END AS ContributionLevel,
  COALESCE(CAST(upc.TotalViewCount AS VARCHAR), 'N/A') AS TotalViewsStr,
  upc.LastPostDate,
  upc.TotalFavoriteCount,
  hsa.Title AS TopAnswerTitle,
  hsa.Score AS TopAnswerScore,
  (
    SELECT
      SUM(p.AnswerCount)
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId = upc.UserId
      AND p.PostTypeId = 1
      AND p.AnswerCount > 0
  ) AS TotalAnswersToTheirQuestions,
  CASE
    WHEN upc.LastPostDate BETWEEN DATE_SUB(NOW(), INTERVAL 1 YEAR) AND NOW() THEN 'Active'
    ELSE 'Inactive'
  END AS ActivityStatus
FROM
  UserPostContribution AS upc
  LEFT JOIN HighScoringQuestions AS hsq ON upc.UserId = hsq.OwnerUserId
  LEFT JOIN HighScoringAnswers AS hsa ON upc.UserId = hsa.OwnerUserId
WHERE
  upc.Reputation > 1000
  AND upc.TotalPosts > 50
ORDER BY
  upc.Reputation DESC
LIMIT 100;
