WITH UserPostActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
    MAX(p.CreationDate) AS LatestPostDate,
    AVG(p.Score) AS AveragePostScore,
    SUM(p.FavoriteCount) AS TotalFavorites
  FROM Users u
  LEFT JOIN Posts p
    ON u.Id = p.OwnerUserId
  LEFT JOIN PostTypes pt
    ON p.PostTypeId = pt.Id
  GROUP BY
    u.Id,
    u.DisplayName
), PostEngagement AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    COUNT(c.Id) AS CommentCountTotal,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn,
    p.CreationDate
  FROM Posts p
  LEFT JOIN Comments c
    ON p.Id = c.PostId
  LEFT JOIN Votes v
    ON p.Id = v.PostId
  WHERE
    p.PostTypeId = 1
  GROUP BY
    p.Id,
    p.Title,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate
), RecentQuestions AS (
  SELECT
    pe.PostId,
    pe.Title,
    pe.Score,
    pe.AnswerCount,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.CommentCountTotal,
    pe.UpVoteCount,
    pe.DownVoteCount,
    ROW_NUMBER() OVER (ORDER BY pe.Score DESC) AS RankByScore,
    pe.CreationDate
  FROM PostEngagement pe
  WHERE
    pe.rn = 1
    AND pe.Score > 5
    AND pe.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90' DAY)
), TaggedQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    t.TagName,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS TagRank,
    p.CreationDate,
    p.Tags
  FROM Posts p
  JOIN Tags t
    ON POSITION(t.TagName IN SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2))) > 0
  WHERE
    p.PostTypeId = 1
    AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180' DAY)
), UserContributionSummary AS (
  SELECT
    upa.UserId,
    upa.DisplayName,
    upa.TotalPosts,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.AveragePostScore,
    upa.TotalFavorites,
    CASE
      WHEN upa.TotalPosts IS NULL THEN 'No Posts'
      WHEN upa.TotalPosts > 1000 THEN 'Power User'
      WHEN upa.TotalPosts > 100 THEN 'Active User'
      ELSE 'New User'
    END AS UserCategory
  FROM UserPostActivity upa
), TopQuestionsWithTags AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Score,
    rq.AnswerCount,
    rq.FavoriteCount,
    tq.TagName
  FROM RecentQuestions rq
  JOIN TaggedQuestions tq
    ON rq.PostId = tq.PostId
  WHERE
    tq.TagRank <= 3
), TopQuestionsWithTags_Ranked AS (
  SELECT
    PostId,
    Title,
    Score,
    TagName,
    FavoriteCount,
    ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY FavoriteCount DESC) AS QuestionFavRank
  FROM TopQuestionsWithTags
)
SELECT
  ucs.DisplayName,
  ucs.UserCategory,
  ucs.TotalPosts,
  ucs.QuestionCount,
  ucs.AnswerCount,
  ucs.AveragePostScore,
  COALESCE(tqwt.Title, 'N/A') AS TopTaggedQuestionTitle,
  COALESCE(tqwt.TagName, 'N/A') AS TopTag,
  COALESCE(tqwt.Score, 0) AS TopTaggedQuestionScore
FROM UserContributionSummary ucs
LEFT JOIN TopQuestionsWithTags_Ranked tqwt
  ON tqwt.QuestionFavRank = 1
  AND tqwt.PostId = (
    SELECT p.OwnerUserId -- this subquery originally matched OwnerUserId to UserId; adjust to find a post by this user
    FROM Posts p
    JOIN TopQuestionsWithTags tqt ON p.Id = tqt.PostId
    WHERE p.OwnerUserId = ucs.UserId
    ORDER BY tqt.FavoriteCount DESC
    LIMIT 1
  )
WHERE
  ucs.TotalPosts > 10

UNION ALL

SELECT
  'Community Performance Analysis' AS DisplayName,
  'Global Metrics' AS UserCategory,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  COUNT(CASE WHEN pt.Name = 'Question' THEN p.Id END) AS QuestionCount,
  COUNT(CASE WHEN pt.Name = 'Answer' THEN p.Id END) AS AnswerCount,
  AVG(p.Score) AS AveragePostScore,
  MAX(best_posts.Title) AS TopTaggedQuestionTitle,
  'Overall' AS TopTag,
  MAX(best_posts.Score) AS TopTaggedQuestionScore
FROM Posts p
JOIN PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN (
  SELECT
    PostId,
    Title,
    Score,
    OverallRank
  FROM (
    SELECT
      PostId,
      Title,
      Score,
      ROW_NUMBER() OVER (ORDER BY Score DESC) AS OverallRank,
      rn
    FROM PostEngagement
  ) pe2
  WHERE rn = 1
) best_posts
  ON p.Id = best_posts.PostId
WHERE
  best_posts.OverallRank <= 100
ORDER BY
  DisplayName,
  AveragePostScore DESC;