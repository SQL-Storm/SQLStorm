-- {"query": "45060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 137640, "output_tokens": 24323} 
WITH TopTagUsers AS (
    SELECT t.TagName, u.Id, u.DisplayName, 
           COUNT(p.Id) AS PostCount,
           DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(p.Id) DESC) AS UserRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%>' || t.TagName || '<%'
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, u.Id, u.DisplayName
)
SELECT 
    TagName, 
    Id AS UserId, 
    DisplayName, 
    PostCount,
    (SELECT AVG(v.Score) 
     FROM Posts p 
     JOIN Votes v ON p.Id = v.PostId 
     WHERE p.OwnerUserId = TopTagUsers.Id 
     AND p.Tags LIKE '%>' || TopTagUsers.TagName || '<%') AS AvgVoteScore
FROM TopTagUsers
WHERE UserRank <= 5
ORDER BY TagName, PostCount DESC
LIMIT 100;