-- {"query": "26028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 534} 

WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, COUNT(DISTINCT p.Id) AS PostCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.Score > 10
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 100
),
TopTags AS (
    SELECT t.TagName, COUNT(DISTINCT p.Id) AS PostCount
    FROM Tags t
    JOIN Posts p ON t.Id = ANY(string_to_array(p.Tags, '><'))
    WHERE p.PostTypeId = 1 AND p.Score > 10
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p.Id) > 100
),
PostScores AS (
    SELECT p.Id, p.Score, ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 10
),
CommentCounts AS (
    SELECT p.Id, COUNT(c.Id) AS CommentCount
    FROM Posts p
    JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 AND p.Score > 10
    GROUP BY p.Id
),
VoteCounts AS (
    SELECT p.Id, COUNT(v.Id) AS VoteCount
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 AND v.VoteTypeId = 2
    GROUP BY p.Id
)
SELECT 
    u.Id, 
    u.DisplayName, 
    p.Id AS PostId, 
    p.Score, 
    ps.RowNum, 
    cc.CommentCount, 
    vc.VoteCount, 
    t.TagName, 
    tu.PostCount AS UserPostCount, 
    tt.PostCount AS TagPostCount
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN PostScores ps ON p.Id = ps.Id
JOIN CommentCounts cc ON p.Id = cc.Id
JOIN VoteCounts vc ON p.Id = vc.Id
JOIN Tags t ON t.Id = ANY(string_to_array(p.Tags, '><'))
JOIN TopUsers tu ON u.Id = tu.Id
JOIN TopTags tt ON t.TagName = tt.TagName
WHERE p.PostTypeId = 1 AND p.Score > 10
AND tu.PostCount > 100 AND tt.PostCount > 100
AND ps.RowNum < 100
ORDER BY p.Score DESC, ps.RowNum ASC;
