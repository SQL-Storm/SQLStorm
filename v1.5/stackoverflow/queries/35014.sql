-- {"query": "35014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 833} 
WITH cte_reputation_growth AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        DATE_TRUNC('month', u.CreationDate) AS Month,
        SUM(p.Score) AS MonthlyScore,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 100 ELSE 0 END),0) +
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 20 ELSE 0 END),0) +
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 10 ELSE 0 END),0) AS MonthlyBadgeBonus
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= u.CreationDate
    LEFT JOIN Badges b ON b.UserId = u.Id AND DATE_TRUNC('month', b.Date) = DATE_TRUNC('month', p.CreationDate)
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, DATE_TRUNC('month', u.CreationDate)
),
user_activity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        MAX(p.Score) AS MaxPostScore,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score END) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id
),
hot_questions AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        COUNT(a.Id) AS AnswerCount
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
      AND p.ViewCount > 5000
      AND p.Score > 10
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AcceptedAnswerId
),
duplicate_links AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        p.OwnerUserId AS SourceUser,
        r.OwnerUserId AS TargetUser,
        COUNT(*) AS DuplicateCount
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    JOIN Posts r ON pl.RelatedPostId = r.Id
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId, pl.RelatedPostId, p.OwnerUserId, r.OwnerUserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    ua.TotalPosts,
    ua.TotalComments,
    ua.MaxPostScore,
    ua.AvgPostScore,
    SUM(crg.MonthlyScore + crg.MonthlyBadgeBonus) AS TotalScoreWithBadges,
    COUNT(DISTINCT hq.PostId) AS NumHotQuestions,
    SUM(hq.AnswerCount) AS TotalAnswersOnHotQuestions,
    COUNT(DISTINCT dl.PostId) AS NumDuplicatesCreated,
    COUNT(DISTINCT dl.RelatedPostId) AS NumDuplicatesReceived
FROM Users u
LEFT JOIN cte_reputation_growth crg ON crg.UserId = u.Id
LEFT JOIN user_activity ua ON ua.UserId = u.Id
LEFT JOIN hot_questions hq ON hq.OwnerUserId = u.Id
LEFT JOIN duplicate_links dl ON dl.SourceUser = u.Id
LEFT JOIN duplicate_links dl2 ON dl2.TargetUser = u.Id
WHERE u.Reputation > 1000
GROUP BY
    u.Id, u.DisplayName, ua.TotalPosts, ua.TotalComments, ua.MaxPostScore, ua.AvgPostScore
ORDER BY TotalScoreWithBadges DESC, NumHotQuestions DESC
LIMIT 50;