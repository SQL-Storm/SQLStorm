-- {"query": "45012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 420}
WITH UserPostInteractions AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalQuestionViews
    FROM 
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    upi.UserId,
    upi.DisplayName,
    upi.QuestionCount,
    upi.VoteCount,
    upi.CommentCount,
    upi.AvgQuestionScore,
    upi.TotalQuestionViews,
    t.TagName AS TopTag,
    COUNT(DISTINCT pl.Id) AS PostLinkCount
FROM 
    UserPostInteractions upi
JOIN Tags t ON t.Count = (
    SELECT MAX(Count) 
    FROM Tags
)
LEFT JOIN Posts p ON upi.UserId = p.OwnerUserId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
WHERE 
    upi.QuestionCount > 10 AND 
    upi.AvgQuestionScore > 2
ORDER BY 
    upi.TotalQuestionViews DESC, 
    upi.VoteCount DESC
LIMIT 100;
