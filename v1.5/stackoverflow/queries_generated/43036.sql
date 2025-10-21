-- {"query": "43036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 588} 

WITH UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        MAX(b.Date) AS LastBadgeEarned
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
CommentAnalysis AS (
    SELECT 
        p.Id AS PostId,
        COUNT(c.Id) AS TotalComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY p.Id
),
PostRevisionStats AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId BETWEEN 4 AND 6 THEN 1 END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId BETWEEN 10 AND 11 THEN 1 END) AS CloseReopenCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
)
SELECT
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalQuestionViews,
    ua.AvgQuestionScore,
    ua.LastBadgeEarned,
    ca.TotalComments,
    ca.AvgCommentLength,
    prs.EditCount,
    prs.CloseReopenCount,
    prs.LastEditDate
FROM UserActivity ua
LEFT JOIN Posts p ON ua.Id = p.OwnerUserId
LEFT JOIN CommentAnalysis ca ON p.Id = ca.PostId
LEFT JOIN PostRevisionStats prs ON p.Id = prs.PostId
WHERE ua.QuestionCount > 10 AND ua.AvgQuestionScore > 15
ORDER BY ua.TotalQuestionViews DESC, prs.EditCount DESC
LIMIT 100;
