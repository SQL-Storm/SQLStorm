-- {"query": "56053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 358} 

WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, SUM(v.BountyAmount) AS TotalBounty
    FROM Users u
    JOIN Votes v ON u.Id = v.UserId
    WHERE v.VoteTypeId = 8
    GROUP BY u.Id, u.DisplayName
    ORDER BY TotalBounty DESC
    LIMIT 10
),
TopPosts AS (
    SELECT p.Id, p.Title, COUNT(DISTINCT ph.PostId) AS EditCount
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY p.Id, p.Title
    ORDER BY EditCount DESC
    LIMIT 10
),
QuestionTags AS (
    SELECT p.Id, p.Title, t.TagName
    FROM Posts p
    JOIN PostTags pt ON p.Id = pt.PostId
    JOIN Tags t ON pt.TagId = t.Id
    WHERE p.PostTypeId = 1
)
SELECT 
    u.DisplayName, 
    p.Title, 
    ph.Comment, 
    ph.CreationDate, 
    v.VoteTypeId, 
    vt.Name, 
    t.TagName
FROM Users u
JOIN PostHistory ph ON u.Id = ph.UserId
JOIN Posts p ON ph.PostId = p.Id
JOIN Votes v ON p.Id = v.PostId
JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
JOIN QuestionTags qt ON p.Id = qt.Id
JOIN Tags t ON qt.TagName = t.TagName
WHERE u.Id IN (SELECT Id FROM TopUsers)
AND p.Id IN (SELECT Id FROM TopPosts)
ORDER BY ph.CreationDate DESC;
