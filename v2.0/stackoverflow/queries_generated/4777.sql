-- {"query": "4777.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1399} 

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
  FROM Users AS u
  LEFT JOIN Posts AS p
    ON u.Id = p.OwnerUserId
  LEFT JOIN PostTypes AS pt
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
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn
  FROM Posts AS p
  LEFT JOIN Comments AS c
    ON p.Id = c.PostId
  LEFT JOIN Votes AS v
    ON p.Id = v.PostId
  WHERE
    p.PostTypeId = 1 -- Only consider questions for this analysis
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
    ROW_NUMBER() OVER (ORDER BY pe.Score DESC) AS RankByScore
  FROM PostEngagement AS pe
  WHERE
    pe.rn = 1 AND pe.Score > 5 AND pe.CreationDate > NOW() - INTERVAL '90 days'
), TaggedQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    t.TagName,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS TagRank
  FROM Posts AS p
  JOIN Tags AS t
    ON SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) LIKE '%' || t.TagName || '%' -- Simple tag matching
  WHERE
    p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '180 days'
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
  FROM UserPostActivity AS upa
), TopQuestionsWithTags AS (
  SELECT
    rq.Title,
    rq.Score,
    rq.AnswerCount,
    rq.FavoriteCount,
    tq.TagName
  FROM RecentQuestions AS rq
  JOIN TaggedQuestions AS tq
    ON rq.PostId = tq.PostId
  WHERE
    tq.TagRank <= 3
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
FROM UserContributionSummary AS ucs
LEFT JOIN (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY FavoriteCount DESC) as QuestionFavRank
  FROM TopQuestionsWithTags
) AS tqwt
  ON ucs.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = (SELECT PostId FROM TopQuestionsWithTags ORDER BY FavoriteCount DESC LIMIT 1)) AND tqwt.QuestionFavRank = 1
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
  MAX(Title) AS TopTaggedQuestionTitle,
  'Overall' AS TopTag,
  MAX(Score) AS TopTaggedQuestionScore
FROM Posts AS p
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN (
  SELECT
    PostId,
    Title,
    Score,
    ROW_NUMBER() OVER (ORDER BY Score DESC) AS OverallRank
  FROM PostEngagement
  WHERE
    rn = 1
) AS best_posts
  ON p.Id = best_posts.PostId
WHERE
  best_posts.OverallRank <= 100
ORDER BY
  DisplayName,
  AveragePostScore DESC;
