-- {"query": "51043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1397} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT ph.Id) AS TotalEdits,
        COUNT(DISTINCT v.Id) AS TotalVotesReceived,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS ReputationRankByYear,
        DENSE_RANK() OVER (ORDER BY SUM(p.Score) DESC) AS OverallScoreRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation >= 1
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
TopContributors AS (
    SELECT 
        ua.*,
        LAG(ua.TotalPosts) OVER (ORDER BY ua.UserId) AS PrevUserPostCount,
        LEAD(ua.TotalPosts) OVER (ORDER BY ua.UserId) AS NextUserPostCount
    FROM UserActivity ua
    WHERE ua.TotalPosts >= 10 OR ua.Reputation >= 1000
),
QuestionMetrics AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.ClosedDate,
        COALESCE(accepted.Score, 0) AS AcceptedAnswerScore,
        COUNT(CASE WHEN ans.Score > 0 THEN 1 END) AS PositiveAnswerCount,
        AVG(ans.Score) AS AvgAnswerScore,
        STRING_AGG(DISTINCT SUBSTRING(t.TagName FROM 1 FOR 20), ', ') AS TopTags,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(MONTH FROM p.CreationDate) ORDER BY p.ViewCount DESC) AS MonthlyViewRank
    FROM Posts p
    LEFT JOIN Posts ans ON p.Id = ans.ParentId AND ans.PostTypeId = 2
    LEFT JOIN Posts accepted ON p.AcceptedAnswerId = accepted.Id
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1
    LEFT JOIN Posts linked ON pl.RelatedPostId = linked.Id AND linked.PostTypeId = 1
    LEFT JOIN (
        SELECT DISTINCT SUBSTRING(Tags FROM '<([^>]*)>' AS tag FROM Posts WHERE PostTypeId = 1 AND Tags IS NOT NULL
    ) AS tag_extract ON true
    LEFT JOIN Tags t ON tag_extract.tag = t.TagName
    WHERE p.PostTypeId = 1 AND p.DeletedDate IS NULL
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, 
             p.FavoriteCount, p.CreationDate, p.ClosedDate, accepted.Score
),
EngagementTrends AS (
    SELECT 
        EXTRACT(YEAR FROM p.CreationDate) AS Year,
        EXTRACT(MONTH FROM p.CreationDate) AS Month,
        COUNT(*) AS MonthlyPosts,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT p.OwnerUserId) AS ActiveUsers,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS Questions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS Answers,
        AVG(p.AnswerCount) AS AvgAnswersPerQuestion,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p.ViewCount) AS P90Views,
        CORR(p.Score, p.ViewCount) AS ScoreViewCorrelation
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
    GROUP BY Year, Month
)
SELECT 
    tc.UserId,
    tc.DisplayName AS OwnerDisplayName,
    tc.Reputation,
    tc.TotalPosts,
    tc.QuestionsAsked,
    tc.AnswersGiven,
    tc.AvgPostScore,
    tc.TotalViews,
    tc.BadgeCount,
    tc.ReputationRankByYear,
    tc.OverallScoreRank,
    qm.QuestionId,
    qm.Title AS RecentQuestionTitle,
    qm.QuestionScore,
    qm.ViewCount AS RecentQuestionViews,
    qm.AcceptedAnswerScore,
    qm.PositiveAnswerCount,
    et.Year,
    et.Month,
    et.MonthlyPosts,
    et.AvgScore AS MonthlyAvgScore,
    et.ActiveUsers,
    CASE 
        WHEN tc.TotalPosts > (tc.PrevUserPostCount + tc.NextUserPostCount) / 2 THEN 'High Activity'
        WHEN tc.Reputation > 5000 THEN 'Elite Contributor'
        ELSE 'Regular'
    END AS UserTier,
    (tc.TotalViews::float / NULLIF(tc.TotalPosts, 0)) AS ViewsPerPost,
    RANK() OVER (PARTITION BY et.Year ORDER BY tc.Reputation DESC) AS YearlyReputationRank
FROM TopContributors tc
LEFT JOIN (
    SELECT DISTINCT ON (OwnerUserId) 
        OwnerUserId, 
        QuestionId, Title, QuestionScore, ViewCount, AcceptedAnswerScore, 
        PositiveAnswerCount
    FROM QuestionMetrics 
    ORDER BY OwnerUserId, CreationDate DESC
) qm ON tc.UserId = qm.OwnerUserId
CROSS JOIN LATERAL (
    SELECT * FROM EngagementTrends 
    WHERE Year = EXTRACT(YEAR FROM tc.UserCreationDate)
    ORDER BY ABS(Month - EXTRACT(MONTH FROM CURRENT_DATE)) 
    LIMIT 3
) et
WHERE tc.UserCreationDate >= CURRENT_DATE - INTERVAL '2 years'
  AND (tc.TotalPosts >= 5 OR tc.BadgeCount > 0)
ORDER BY tc.OverallScoreRank, et.Year DESC, et.Month DESC
LIMIT 1000;
