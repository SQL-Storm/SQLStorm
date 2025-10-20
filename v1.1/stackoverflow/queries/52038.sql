WITH UserEngagement AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS QuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS AnswerScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS AcceptedQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ParentId IN (SELECT Id FROM Posts WHERE PostTypeId = 1) THEN p.Id END) AS AnswersToQuestions,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 20 WHEN b.Class = 2 THEN 10 WHEN b.Class = 3 THEN 5 ELSE 0 END), 0) AS BadgePoints,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyEarned,
        MAX(p.LastActivityDate) AS LatestPostActivity,
        AVG(p.ViewCount) AS AvgViewCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.PostId = p.Id
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 0 AND COUNT(DISTINCT b.Id) > 0
),
RankedUsers AS (
    SELECT 
        ue.Id,
        ue.DisplayName,
        ue.Reputation,
        ue.CreationDate,
        ue.TotalPosts,
        ue.QuestionScore,
        ue.AnswerScore,
        ue.AcceptedQuestions,
        ue.AnswersToQuestions,
        ue.BadgeCount,
        ue.BadgePoints,
        ue.CommentCount,
        ue.VoteCount,
        ue.TotalBountyEarned,
        ue.LatestPostActivity,
        ue.AvgViewCount,
        (ue.QuestionScore + ue.AnswerScore + ue.BadgePoints + ue.CommentCount + ue.VoteCount + ue.TotalBountyEarned) AS EngagementScore,
        ROW_NUMBER() OVER (ORDER BY (ue.QuestionScore + ue.AnswerScore + ue.BadgePoints + ue.CommentCount + ue.VoteCount + ue.TotalBountyEarned) DESC, ue.Reputation DESC) AS Rank
    FROM UserEngagement ue
    WHERE ue.Reputation >= 100
      AND (EXTRACT(YEAR FROM TIMESTAMP '2024-10-01 12:34:56') - EXTRACT(YEAR FROM ue.CreationDate)
           - CASE 
               WHEN (EXTRACT(MONTH FROM TIMESTAMP '2024-10-01 12:34:56') < EXTRACT(MONTH FROM ue.CreationDate))
                 OR (EXTRACT(MONTH FROM TIMESTAMP '2024-10-01 12:34:56') = EXTRACT(MONTH FROM ue.CreationDate)
                     AND EXTRACT(DAY FROM TIMESTAMP '2024-10-01 12:34:56') < EXTRACT(DAY FROM ue.CreationDate))
             THEN 1 ELSE 0 END
          ) > 1
),
PostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT pl.Id) AS LinkedPostsCount,
        COUNT(DISTINCT ph.Id) AS HistoryEvents,
        AVG(LENGTH(p.Body)) AS AvgBodyLength,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END) AS CloseOrDeleteEvents
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    GROUP BY p.OwnerUserId
)
SELECT 
    ru.DisplayName,
    ru.Reputation,
    ru.TotalPosts,
    ru.QuestionScore,
    ru.AnswerScore,
    ru.AcceptedQuestions,
    ru.AnswersToQuestions,
    ru.BadgeCount,
    ru.BadgePoints,
    ru.CommentCount,
    ru.VoteCount,
    ru.TotalBountyEarned,
    ru.EngagementScore,
    ru.Rank,
    ps.LinkedPostsCount,
    ps.HistoryEvents,
    ps.AvgBodyLength,
    ps.CloseOrDeleteEvents,
    ru.LatestPostActivity,
    ru.AvgViewCount
FROM RankedUsers ru
JOIN PostStats ps ON ru.Id = ps.OwnerUserId
WHERE ru.Rank <= 50
ORDER BY ru.Rank, ru.Reputation DESC;