-- {"query": "17061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 144770, "output_tokens": 143785} 

WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        DATE_PART('year', AGE(CURRENT_DATE, u.CreationDate)) AS YearsActive,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        SUM(CASE WHEN p.Score IS NULL THEN 0 ELSE p.Score END) AS TotalScore,
        AVG(CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Score END) AS AvgAnswerScore,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ' ORDER BY b.Name) AS GoldBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate < CURRENT_DATE - INTERVAL '6 months'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 0
),
TagExperts AS (
    SELECT 
        t.TagName,
        p.OwnerUserId,
        COUNT(*) AS TagPosts,
        SUM(p.Score) AS TagScore,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC, COUNT(*) DESC) AS ExpertRank,
        DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) AS TagActivityRank
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.OwnerUserId IS NOT NULL 
        AND p.Score > 0
        AND t.Count >= 100
    GROUP BY t.TagName, p.OwnerUserId
),
QuestionAnalysis AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate AS QuestionDate,
        q.ViewCount,
        q.Score AS QuestionScore,
        COALESCE(q.AnswerCount, 0) AS AnswerCount,
        a.Id AS BestAnswerId,
        a.OwnerUserId AS BestAnswerUserId,
        a.Score AS BestAnswerScore,
        CASE 
            WHEN a.CreationDate IS NULL THEN NULL
            ELSE EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600
        END AS HoursToAnswer,
        FIRST_VALUE(a2.Score) OVER (
            PARTITION BY q.Id 
            ORDER BY a2.Score DESC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS HighestAnswerScore,
        (
            SELECT COUNT(DISTINCT ph.UserId)
            FROM PostHistory ph
            WHERE ph.PostId = q.Id 
                AND ph.PostHistoryTypeId IN (4, 5, 6)
                AND ph.UserId != q.OwnerUserId
        ) AS UniqueEditors,
        EXISTS (
            SELECT 1 
            FROM PostLinks pl 
            WHERE pl.RelatedPostId = q.Id 
                AND pl.LinkTypeId = 3
        ) AS IsDuplicateTarget,
        SUBSTRING(
            q.Body, 
            1, 
            LEAST(POSITION('?' IN q.Body), POSITION('.' IN q.Body), 100)
        ) AS BodyStart
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
    LEFT JOIN Posts a2 ON a2.ParentId = q.Id AND a2.PostTypeId = 2
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND q.Score >= 0
        AND (q.ClosedDate IS NULL OR q.ClosedDate > q.CreationDate + INTERVAL '7 days')
),
UserActivity AS (
    SELECT 
        UserId,
        DATE_TRUNC('month', CreationDate) AS ActivityMonth,
        COUNT(*) AS Actions,
        LAG(COUNT(*), 1, 0) OVER (
            PARTITION BY UserId 
            ORDER BY DATE_TRUNC('month', CreationDate)
        ) AS PrevMonthActions,
        LEAD(COUNT(*), 1, 0) OVER (
            PARTITION BY UserId 
            ORDER BY DATE_TRUNC('month', CreationDate)
        ) AS NextMonthActions
    FROM (
        SELECT UserId, CreationDate FROM Comments WHERE UserId IS NOT NULL
        UNION ALL
        SELECT UserId, CreationDate FROM Votes WHERE UserId IS NOT NULL
        UNION ALL  
        SELECT UserId, CreationDate FROM PostHistory WHERE UserId IS NOT NULL
    ) activities
    GROUP BY UserId, DATE_TRUNC('month', CreationDate)
)
SELECT 
    um.DisplayName,
    um.Reputation,
    UPPER(LEFT(um.Location, 2)) || LOWER(SUBSTRING(um.Location, 3, 10)) AS FormattedLocation,
    um.YearsActive,
    um.Questions + um.Answers AS TotalQA,
    ROUND(um.TotalScore::NUMERIC / NULLIF(um.TotalPosts, 0), 2) AS AvgPostScore,
    COALESCE(um.AvgAnswerScore, 0) AS AvgAnswerScore,
    te.TagName AS TopExpertiseTag,
    te.TagScore AS ExpertiseScore,
    COUNT(DISTINCT qa.QuestionId) AS HighQualityQuestions,
    AVG(qa.HoursToAnswer) FILTER (WHERE qa.HoursToAnswer IS NOT NULL) AS AvgHoursToAcceptedAnswer,
    MAX(qa.ViewCount) AS MaxQuestionViews,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qa.AnswerCount) AS MedianAnswersPerQuestion,
    SUM(CASE WHEN qa.IsDuplicateTarget THEN 1 ELSE 0 END) AS DuplicateTargets,
    COALESCE(um.GoldBadges, 'None') AS GoldBadges,
    MAX(ua.Actions) AS PeakMonthlyActivity,
    AVG(ABS(ua.Actions - ua.PrevMonthActions)) AS AvgActivityVariance
FROM UserMetrics um
LEFT JOIN LATERAL (
    SELECT te2.*
    FROM TagExperts te2
    WHERE te2.OwnerUserId = um.Id 
        AND te2.ExpertRank = 1
    ORDER BY te2.TagScore DESC
    LIMIT 1
) te ON true
LEFT JOIN QuestionAnalysis qa ON qa.OwnerUserId = um.Id
    AND qa.QuestionScore >= 5
    AND qa.ViewCount > 1000
LEFT JOIN UserActivity ua ON ua.UserId = um.Id
WHERE um.Reputation > 1000
    AND um.TotalPosts >= 10
    AND (te.TagName IS NOT NULL OR um.Questions > 5)
GROUP BY 
    um.Id, um.DisplayName, um.Reputation, um.Location, 
    um.YearsActive, um.Questions, um.Answers, um.TotalScore,
    um.TotalPosts, um.AvgAnswerScore, um.GoldBadges,
    te.TagName, te.TagScore
HAVING COUNT(DISTINCT qa.QuestionId) > 0 
    OR SUM(CASE WHEN qa.AnswerCount > 5 THEN 1 ELSE 0 END) > 2
ORDER BY 
    um.Reputation DESC,
    COALESCE(te.TagScore, 0) DESC,
    um.TotalScore DESC
LIMIT 100;
