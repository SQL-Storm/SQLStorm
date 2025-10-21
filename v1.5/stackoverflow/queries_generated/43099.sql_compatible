WITH UserActivity AS (
    SELECT 
        u.Id, 
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 AND p.CreationDate > DATE '2024-10-01' - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.PostTypeId = 1 AND p.CreationDate > DATE '2024-10-01' - INTERVAL '1 year'
    GROUP BY t.TagName
    ORDER BY PostCount DESC
    LIMIT 10
),
QuestionDetails AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        COUNT(DISTINCT ph.Id) AS EditCount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Score
    HAVING COUNT(DISTINCT ph.Id) > 10 AND COUNT(DISTINCT c.Id) > 5
)
SELECT 
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalScore,
    ua.AvgScore,
    ua.LastBadgeDate,
    tt.TagName,
    qd.Title,
    qd.Score,
    qd.EditCount,
    qd.CommentCount
FROM UserActivity ua
CROSS JOIN TopTags tt
LEFT JOIN QuestionDetails qd ON qd.Id = (
    SELECT p.Id FROM Posts p WHERE p.Id = qd.Id LIMIT 1
)
ORDER BY ua.TotalScore DESC, qd.Score DESC;