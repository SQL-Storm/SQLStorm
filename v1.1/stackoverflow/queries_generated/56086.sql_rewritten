-- {"query": "56086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 310} 
WITH TopUsers AS (
  SELECT u.Id, u.DisplayName, COUNT(DISTINCT p.Id) AS PostCount
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName
  ORDER BY PostCount DESC
  LIMIT 10
),
TopPosts AS (
  SELECT p.Id, p.Title, COUNT(DISTINCT c.Id) AS CommentCount
  FROM Posts p
  JOIN Comments c ON p.Id = c.PostId
  GROUP BY p.Id, p.Title
  ORDER BY CommentCount DESC
  LIMIT 10
),
PostVotes AS (
  SELECT p.Id, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Posts p
  JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.Id
)
SELECT 
  tu.DisplayName AS TopUser,
  tp.Title AS TopPost,
  pv.UpVotes,
  pv.DownVotes,
  ph.Comment AS PostHistoryComment
FROM TopUsers tu
JOIN Posts p ON tu.Id = p.OwnerUserId
JOIN TopPosts tp ON p.Id = tp.Id
JOIN PostVotes pv ON p.Id = pv.Id
JOIN PostHistory ph ON p.Id = ph.PostId
WHERE ph.PostHistoryTypeId = 10
ORDER BY pv.UpVotes DESC;