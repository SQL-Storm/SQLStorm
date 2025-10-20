-- {"query": "21009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 2237} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        AVG(p.Score) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.DeletionDate IS NULL
    WHERE u.Reputation >= 100 
      AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
    HAVING COUNT(DISTINCT p.Id) > 0
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.ClosedDate,
        p.Title,
        LENGTH(p.Body) AS BodyLength,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AnswerCount >= 3 THEN 'WellAnswered'
            WHEN p.Score < 0 THEN 'Negative'
            ELSE 'Active'
        END AS QuestionStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentRank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevQuestionScore,
        LEAD(p.AnswerCount, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextQuestionAnswers,
        NTILE(4) OVER (ORDER BY p.ViewCount DESC) AS ViewQuartile,
        STRING_AGG(DISTINCT SUBSTRING(t.TagName FROM 1 FOR 20), ', ') AS TopTags
    FROM Posts p
    LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1 
      AND p.DeletionDate IS NULL
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, 
             p.AnswerCount, p.CommentCount, p.ClosedDate, p.Title, p.Body
),
AnswerContributions AS (
    SELECT 
        a.OwnerUserId,
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        COUNT(DISTINCT c.Id) AS CommentCountOnAnswers,
        MAX(a.LastEditDate) AS LastAnswerActivity
    FROM Posts a
    LEFT JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Votes v ON a.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON a.Id = c.PostId
    WHERE a.PostTypeId = 2 
      AND a.DeletionDate IS NULL
      AND a.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY a.OwnerUserId, a.ParentId
),
BadgeAchievements AS (
    SELECT 
        b.UserId,
        b.Class,
        COUNT(b.Id) AS BadgeCount,
        STRING_AGG(DISTINCT b.Name, ' | ') AS BadgeNames,
        MAX(b.Date) AS LatestBadgeDate,
        DENSE_RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Badges b
    WHERE b.Date >= CURRENT_DATE - INTERVAL '6 months'
    GROUP BY b.UserId, b.Class
),
ComplexInteractions AS (
    SELECT DISTINCT
        u.Id AS UserId,
        q.QuestionId,
        COALESCE(a.AnswerCount, 0) AS UserAnswersOnQuestion,
        COALESCE(bs.BadgeCount, 0) AS RecentBadges,
        CASE 
            WHEN q.ClosedDate IS NOT NULL AND q.ClosedDate > q.CreationDate + INTERVAL '7 days' 
            THEN 'LateClosed'
            WHEN EXISTS (
                SELECT 1 FROM PostHistory ph 
                WHERE ph.PostId = q.QuestionId 
                  AND ph.PostHistoryTypeId = 10  -- Post Closed
                  AND ph.CreationDate > q.CreationDate
            ) THEN 'VotedClosed'
            ELSE 'Open'
        END AS CloseStatus,
        CASE 
            WHEN q.ViewCount > 10000 THEN 'Viral'
            WHEN q.ViewCount BETWEEN 1000 AND 10000 THEN 'Popular'
            ELSE 'Regular'
        END AS PopularityTier,
        COALESCE((
            SELECT STRING_AGG(DISTINCT vt.Name, ', ') 
            FROM Votes v2 
            JOIN VoteTypes vt ON v2.VoteTypeId = vt.Id
            WHERE v2.PostId = q.QuestionId 
              AND v2.UserId = u.Id
            GROUP BY v2.PostId
        ), 'NoVotes') AS UserVoteTypesOnQuestion
    FROM Users u
    CROSS JOIN QuestionStats q
    LEFT JOIN AnswerContributions a ON u.Id = a.OwnerUserId AND q.QuestionId = a.QuestionId
    LEFT JOIN BadgeAchievements bs ON u.Id = bs.UserId
    WHERE u.Id = q.OwnerUserId
      AND q.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
)
SELECT 
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.TotalPosts,
    au.QuestionsPosted,
    au.AvgPostScore,
    qs.QuestionId,
    qs.Title,
    qs.QuestionStatus,
    qs.ViewCount,
    qs.AvgAnswerScore,
    ci.UserAnswersOnQuestion,
    ci.RecentBadges,
    ci.PopularityTier,
    ci.CloseStatus,
    ci.UserVoteTypesOnQuestion,
    CASE 
        WHEN qs.PrevQuestionScore IS NULL THEN NULL
        WHEN au.UpVotes > au.DownVotes * 2 THEN 'Improving'
        WHEN qs.Score > COALESCE(qs.PrevQuestionScore, 0) + 5 THEN 'ScoreIncrease'
        WHEN qs.ViewQuartile = 1 AND qs.AnswerCount >= 5 THEN 'HighImpact'
        ELSE 'Standard'
    END AS PerformanceCategory,
    (qs.ViewCount * 0.6 + qs.Score * 10 + COALESCE(qs.AvgAnswerScore, 0) * 5) AS EngagementScore,
    GREATEST(qs.BodyLength / 1000.0, 1) AS BodyComplexity,
    CASE 
        WHEN ci.UserVoteTypesOnQuestion LIKE '%UpMod%' THEN 'ActiveVoter'
        WHEN LENGTH(qs.TopTags) > 50 THEN 'MultiTagExpert'
        WHEN au.Reputation > 5000 AND ci.RecentBadges >= 3 THEN 'VeteranAchiever'
        ELSE 'GrowingUser'
    END AS UserRole,
    ROW_NUMBER() OVER (PARTITION BY ci.PopularityTier ORDER BY EngagementScore DESC) AS RankInTier,
    PERCENT_RANK() OVER (ORDER BY au.Reputation DESC) AS ReputationPercentile,
    CASE 
        WHEN qs.NextQuestionAnswers IS NOT NULL AND qs.NextQuestionAnswers > qs.AnswerCount 
        THEN 'ImprovingAnswers'
        ELSE 'Stable'
    END AS AnswerTrend
FROM ActiveUsers au
JOIN QuestionStats qs ON au.UserId = qs.OwnerUserId AND qs.RecentRank <= 5
JOIN ComplexInteractions ci ON au.UserId = ci.UserId AND qs.QuestionId = ci.QuestionId
LEFT JOIN (
    SELECT 
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS EditCount,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate))) / 3600 AS AvgHoursToEdit
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4,5,6)  -- Edits
      AND ph.CreationDate > p.CreationDate
    GROUP BY ph.PostId
) edits ON qs.QuestionId = edits.PostId
WHERE (qs.ViewCount > 500 OR qs.Score >= 10)
  AND (au.Reputation <= 10000 OR ci.RecentBadges > 0)
  AND NOT (qs.QuestionStatus = 'Negative' AND ci.UserAnswersOnQuestion = 0)
  AND (ci.PopularityTier != 'Regular' OR au.TotalPosts >= 10)
UNION ALL
SELECT 
    NULL AS UserId,
    'Community Aggregate' AS DisplayName,
    AVG(au.Reputation)::int AS Reputation,
    SUM(au.TotalPosts) AS TotalPosts,
    SUM(au.QuestionsPosted) AS QuestionsPosted,
    AVG(au.AvgPostScore) AS AvgPostScore,
    NULL AS QuestionId,
    'Overall Trends' AS Title,
    'Aggregate' AS QuestionStatus,
    SUM(qs.ViewCount) AS ViewCount,
    AVG(qs.AvgAnswerScore) AS AvgAnswerScore,
    AVG(ci.UserAnswersOnQuestion) AS UserAnswersOnQuestion,
    AVG(ci.RecentBadges) AS RecentBadges,
    'All Tiers' AS PopularityTier,
    'Summary' AS CloseStatus,
    'Community' AS UserVoteTypesOnQuestion,
    'AggregateAnalysis' AS PerformanceCategory,
    AVG((qs.ViewCount * 0.6 + qs.Score * 10 + COALESCE(qs.AvgAnswerScore, 0) * 5)) AS EngagementScore,
    AVG(GREATEST(qs.BodyLength / 1000.0, 1)) AS BodyComplexity,
    'Community' AS UserRole,
    NULL AS RankInTier,
    AVG(PERCENT_RANK() OVER (ORDER BY au.Reputation DESC)) AS ReputationPercentile,
    'CommunityTrend' AS AnswerTrend
FROM ActiveUsers au
JOIN QuestionStats qs ON au.UserId = qs.OwnerUserId
JOIN ComplexInteractions ci ON au.UserId = ci.UserId
ORDER BY EngagementScore DESC, Reputation DESC
LIMIT 1000;
