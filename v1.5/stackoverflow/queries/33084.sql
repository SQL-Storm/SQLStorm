-- {"query": "33084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 293} 
SELECT
  p.PostTypeId,
  pt.Name AS PostTypeName,
  COUNT(*) AS TotalPosts,
  AVG(p.Score) AS AvgScore,
  MAX(p.CreationDate) AS MostRecentPost,
  COUNT(DISTINCT p.OwnerUserId) AS UniqueUsers,
  COUNT(c.Id) AS CommentCount,
  AVG(c.Score) FILTER (WHERE c.Score IS NOT NULL) AS AvgCommentScore,
  COUNT(DISTINCT v.UserId) AS Voters,
  COUNT(DISTINCT bl.RelatedPostId) AS LinkedPosts,
  SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AnsweredQuestions,
  COUNT(DISTINCT CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id END) AS ClosedPosts
FROM
  Posts p
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
  LEFT JOIN PostLinks bl ON bl.PostId = p.Id AND bl.LinkTypeId = 1
WHERE
  p.CreationDate BETWEEN '2020-01-01' AND '2021-01-01'
GROUP BY
  p.PostTypeId, pt.Name
ORDER BY
  TotalPosts DESC
LIMIT 100;