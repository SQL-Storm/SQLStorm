-- {"query": "56029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 340} 

WITH TopUsers AS (
  SELECT UserId, COUNT(Id) AS AnswerCount
  FROM Posts
  WHERE PostTypeId = 2
  GROUP BY UserId
  ORDER BY AnswerCount DESC
  LIMIT 10
),
UserReputation AS (
  SELECT u.Id, u.Reputation, 
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Users u
  JOIN Votes v ON u.Id = v.UserId
  GROUP BY u.Id, u.Reputation
),
TopTags AS (
  SELECT t.TagName, COUNT(p.Id) AS PostCount
  FROM Tags t
  JOIN Posts p ON t.Id = ANY(string_to_array(p.Tags, '><'))
  GROUP BY t.TagName
  ORDER BY PostCount DESC
  LIMIT 10
)
SELECT tu.UserId, u.DisplayName, u.Reputation, 
       ur.UpVotes, ur.DownVotes, tt.TagName, 
       COUNT(DISTINCT p.Id) AS PostCount
FROM TopUsers tu
JOIN Users u ON tu.UserId = u.Id
JOIN UserReputation ur ON u.Id = ur.Id
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN Tags t ON t.Id = ANY(string_to_array(p.Tags, '><'))
JOIN TopTags tt ON t.TagName = tt.TagName
GROUP BY tu.UserId, u.DisplayName, u.Reputation, 
         ur.UpVotes, ur.DownVotes, tt.TagName
ORDER BY PostCount DESC;
