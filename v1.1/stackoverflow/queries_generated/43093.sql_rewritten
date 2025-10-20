-- {"query": "43093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 351} 
SELECT 
    u.DisplayName AS "Top Contributor",
    COUNT(DISTINCT q.Id) AS "Total Questions",
    COUNT(DISTINCT a.Id) AS "Total Answers",
    AVG(q.Score) AS "Average Question Score",
    MAX(q.ViewCount) AS "Highest Question Views",
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS "Gold Badges",
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS "Total Upvotes",
    COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN LENGTH(ph.Text) ELSE 0 END), 0) AS "Total Edit Length",
    EXTRACT(YEAR FROM u.CreationDate) AS "Year Joined"
FROM 
    Users u
LEFT JOIN 
    Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1
LEFT JOIN 
    Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
LEFT JOIN 
    PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId = 5
WHERE 
    u.Reputation > 10000
GROUP BY 
    u.Id, u.DisplayName, EXTRACT(YEAR FROM u.CreationDate)
ORDER BY 
    "Total Answers" DESC, "Average Question Score" DESC
LIMIT 10;