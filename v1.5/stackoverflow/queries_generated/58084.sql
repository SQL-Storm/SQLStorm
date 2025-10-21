-- {"query": "58084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1137} 

WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3, 8)
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE 
        u.Reputation > 1000 AND
        p.CreationDate BETWEEN '2020-01-01' AND '2023-12-31' AND
        p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId IN (1, 2))
    GROUP BY u.Id, u.DisplayName, p.Score
),
TagAnalysis AS (
    SELECT 
        PostId,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags)-2), '><'), 1) AS TagCount,
        SUM(AnswerCount) OVER (PARTITION BY OwnerUserId) AS UserTotalAnswers
    FROM Posts
    WHERE PostTypeId = 1 AND Tags IS NOT NULL
)
SELECT 
    au.Id,
    au.DisplayName,
    au.TotalPosts,
    au.TotalComments,
    au.TotalVotes,
    au.TotalBadges,
    au.AvgPostScore,
    ta.TagCount,
    ta.UserTotalAnswers,
    ph.CreationDate AS LastActivity,
    (SELECT COUNT(*) FROM PostHistory WHERE UserId = au.Id AND PostHistoryTypeId = 2) AS EditsMade
FROM ActiveUsers au
JOIN TagAnalysis ta ON au.Id = (SELECT OwnerUserId FROM Posts WHERE Id = ta.PostId LIMIT 1)
JOIN PostHistory ph ON au.Id = ph.UserId AND ph.PostHistoryTypeId IN (5, 6, 10)
WHERE 
    au.PostRank <= 100 AND
    ta.TagCount > 3 AND
    ph.CreationDate = (SELECT MAX(CreationDate) FROM PostHistory WHERE UserId = au.Id)
ORDER BY 
    au.TotalPosts DESC, 
    au.AvgPostScore DESC
LIMIT 100;
