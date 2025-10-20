-- {"query": "48078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 788} 
WITH UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
    AVG(p.Score) AS AveragePostScore,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users AS u
  LEFT JOIN Posts AS p
    ON u.Id = p.OwnerUserId
  LEFT JOIN Comments AS c
    ON u.Id = c.UserId
  LEFT JOIN Votes AS v
    ON u.Id = v.UserId
  LEFT JOIN PostTypes AS pt
    ON p.PostTypeId = pt.Id
  WHERE
    u.Reputation > 1000 AND u.CreationDate < '2023-01-01'
  GROUP BY
    u.Id,
    u.DisplayName
  HAVING
    COUNT(DISTINCT p.Id) > 50
), PostEngagement AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score AS PostScore,
    p.ViewCount,
    p.AnswerCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT pl.Id) AS LinkCount
  FROM Posts AS p
  LEFT JOIN Comments AS c
    ON p.Id = c.PostId
  LEFT JOIN PostLinks AS pl
    ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
  WHERE
    p.PostTypeId = 1 AND p.CreationDate BETWEEN '2022-01-01' AND '2022-12-31'
  GROUP BY
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount
  HAVING
    p.Score > 10 AND p.ViewCount > 1000
)
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.TotalPosts,
  ua.TotalComments,
  ua.TotalVotes,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.AveragePostScore,
  ua.LastPostDate,
  AVG(pe.PostScore) AS AverageEngagedPostScore,
  SUM(pe.ViewCount) AS TotalEngagedPostViews,
  SUM(pe.AnswerCount) AS TotalEngagedPostAnswers,
  SUM(pe.CommentCount) AS TotalEngagedPostComments,
  SUM(pe.LinkCount) AS TotalEngagedPostLinks
FROM UserActivity AS ua
JOIN Posts AS p
  ON ua.UserId = p.OwnerUserId
JOIN PostEngagement AS pe
  ON p.Id = pe.PostId
GROUP BY
  ua.UserId,
  ua.DisplayName,
  ua.TotalPosts,
  ua.TotalComments,
  ua.TotalVotes,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.AveragePostScore,
  ua.LastPostDate
ORDER BY
  ua.AveragePostScore DESC,
  ua.TotalVotes DESC
LIMIT 100;