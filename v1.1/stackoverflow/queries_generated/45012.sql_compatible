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
    SELECT MAX(tt.Count) 
    FROM Tags tt
)
LEFT JOIN Posts p ON upi.UserId = p.OwnerUserId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
WHERE 
    upi.QuestionCount > 10 AND 
    upi.AvgQuestionScore > 2
GROUP BY
    upi.UserId,
    upi.DisplayName,
    upi.QuestionCount,
    upi.VoteCount,
    upi.CommentCount,
    upi.AvgQuestionScore,
    upi.TotalQuestionViews,
    t.TagName
ORDER BY 
    upi.TotalQuestionViews DESC, 
    upi.VoteCount DESC
LIMIT 100;