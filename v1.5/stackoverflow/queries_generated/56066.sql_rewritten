-- {"query": "56066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 393} 
WITH Top10Tags AS (
  SELECT TagName, COUNT(*) as Count
  FROM Tags
  GROUP BY TagName
  ORDER BY Count DESC
  LIMIT 10
),
Top10Users AS (
  SELECT u.Id, u.DisplayName, COUNT(p.Id) as PostCount
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName
  ORDER BY PostCount DESC
  LIMIT 10
),
PostWithTop10Tags AS (
  SELECT p.Id, p.Title, p.Tags, t.TagName
  FROM Posts p
  JOIN PostLinks pl ON p.Id = pl.PostId
  JOIN Tags t ON pl.RelatedPostId = t.Id
  WHERE t.TagName IN (SELECT TagName FROM Top10Tags)
),
PostWithTop10Users AS (
  SELECT p.Id, p.Title, u.DisplayName
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE u.Id IN (SELECT Id FROM Top10Users)
)
SELECT 
  p.Id, 
  p.Title, 
  p.Tags, 
  pwt10t.TagName, 
  pwt10u.DisplayName, 
  COUNT(DISTINCT v.Id) as VoteCount, 
  COUNT(DISTINCT c.Id) as CommentCount
FROM Posts p
JOIN PostWithTop10Tags pwt10t ON p.Id = pwt10t.Id
JOIN PostWithTop10Users pwt10u ON p.Id = pwt10u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
GROUP BY 
  p.Id, 
  p.Title, 
  p.Tags, 
  pwt10t.TagName, 
  pwt10u.DisplayName
ORDER BY VoteCount DESC, CommentCount DESC;