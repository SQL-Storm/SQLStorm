-- {"query": "56042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 392} 

WITH Top10Tags AS (
  SELECT TagName, COUNT(*) AS Count
  FROM Tags
  JOIN PostTags ON Tags.Id = PostTags.TagId
  GROUP BY TagName
  ORDER BY Count DESC
  LIMIT 10
),
Top10Users AS (
  SELECT Users.Id, Users.DisplayName, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes
  FROM Users
  JOIN Posts ON Users.Id = Posts.OwnerUserId
  JOIN Votes ON Posts.Id = Votes.PostId
  GROUP BY Users.Id, Users.DisplayName
  ORDER BY UpVotes DESC
  LIMIT 10
),
PostHistoryStats AS (
  SELECT PostId, PostHistoryTypeId, COUNT(*) AS Count
  FROM PostHistory
  GROUP BY PostId, PostHistoryTypeId
)
SELECT 
  p.Id,
  p.Title,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  phs.Count AS EditCount,
  tt.TagName AS TopTag,
  tu.DisplayName AS TopUser
FROM 
  Posts p
  JOIN PostHistoryStats phs ON p.Id = phs.PostId
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  JOIN PostLinks pl ON p.Id = pl.PostId
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  JOIN Tags t ON p.Id = t.ExcerptPostId
  JOIN Top10Tags tt ON t.TagName = tt.TagName
  JOIN Top10Users tu ON p.OwnerUserId = tu.Id
WHERE 
  p.PostTypeId = 1
  AND phs.PostHistoryTypeId = 5
  AND lt.Name = 'Linked'
  AND p.Score > 100
  AND p.ViewCount > 1000
ORDER BY 
  p.Score DESC, 
  p.ViewCount DESC;
