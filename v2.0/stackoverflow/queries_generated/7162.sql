-- {"query": "7162.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3184} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        Views,
        UpVotes,
        DownVotes,
        TotalPosts,
        Questions,
        Answers,
        Comments,
        Badges,
        TotalQuestionScore,
        TotalAnswerScore,
        LastPostDate,
        LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY TotalQuestionScore DESC, TotalAnswerScore DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as RepRank
    FROM UserActivityStats
    WHERE TotalPosts > 0
),
UserPerformance AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.Views,
        tu.UpVotes,
        tu.DownVotes,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.Comments,
        tu.Badges,
        tu.TotalQuestionScore,
        tu.TotalAnswerScore,
        tu.ScoreRank,
        tu.RepRank,
        CASE 
            WHEN tu.Reputation > 100000 THEN 'Grandmaster'
            WHEN tu.Reputation > 50000 THEN 'Master'
            WHEN tu.Reputation > 10000 THEN 'Expert'
            ELSE 'Regular'
        END as ReputationTier,
        CASE 
            WHEN tu.TotalPosts >= 1000 THEN 'Veteran'
            WHEN tu.TotalPosts >= 500 THEN 'Experienced'
            WHEN tu.TotalPosts >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ActivityLevel,
        (tu.UpVotes - tu.DownVotes) as NetVotes,
        COALESCE(NULLIF(tu.TotalAnswerScore, 0) / NULLIF(tu.Answers, 0), 0) as AvgAnswerScore,
        COALESCE(NULLIF(tu.TotalQuestionScore, 0) / NULLIF(tu.Questions, 0), 0) as AvgQuestionScore,
        DATEDIFF(CURRENT_DATE, tu.LastPostDate) as DaysSinceLastPost,
        DATEDIFF(CURRENT_DATE, tu.LastCommentDate) as DaysSinceLastComment,
        IIF(tu.Badges > 0, 'Badge Holder', 'No Badges') as BadgeStatus
    FROM TopUsers tu
),
PostComplexity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS EngagementMetric,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0 THEN 
                LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '>', '')) + 1
            ELSE 0 
        END AS TagCount,
        CASE 
            WHEN p.Score >= 100 THEN 'Highly Relevant'
            WHEN p.Score >= 50 THEN 'Moderately Relevant'
            WHEN p.Score >= 10 THEN 'Low Relevant'
            ELSE 'Not Relevant'
        END AS RelevanceLevel,
        CASE 
            WHEN p.AnswerCount > 5 THEN 'Well Answered'
            WHEN p.AnswerCount > 0 THEN 'Partially Answered'
            ELSE 'Unanswered'
        END AS AnswerStatus
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2020-01-01'
),
ComplexUserAnalysis AS (
    SELECT 
        up.UserId,
        up.DisplayName,
        up.Reputation,
        up.Views,
        up.UpVotes,
        up.DownVotes,
        up.TotalPosts,
        up.Questions,
        up.Answers,
        up.Comments,
        up.Badges,
        up.TotalQuestionScore,
        up.TotalAnswerScore,
        up.ScoreRank,
        up.RepRank,
        up.ReputationTier,
        up.ActivityLevel,
        up.NetVotes,
        up.AvgAnswerScore,
        up.AvgQuestionScore,
        up.DaysSinceLastPost,
        up.DaysSinceLastComment,
        up.BadgeStatus,
        IIF(up.Reputation > 1000 AND up.Badges > 10 AND up.TotalPosts > 100, 1, 0) as EliteUserFlag,
        RANK() OVER (ORDER BY up.Reputation DESC, up.TotalPosts DESC) as OverallRank
    FROM UserPerformance up
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END AS PopularityLevel,
        CASE 
            WHEN t.IsRequired = 1 THEN 'Required'
            WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only'
            ELSE 'Standard'
        END AS TagType,
        COALESCE((SELECT COUNT(*) FROM Posts WHERE Tags LIKE '%' || t.TagName || '%'), 0) as PostsUsingTag
    FROM Tags t
    WHERE t.Count > 0
)
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN NULL
        ELSE 
            (SELECT COUNT(*) FROM (
                SELECT DISTINCT u.Id 
                FROM Users u 
                INNER JOIN Posts p ON u.Id = p.OwnerUserId 
                INNER JOIN PostHistory ph ON p.Id = ph.PostId 
                INNER JOIN Badges b ON u.Id = b.UserId 
                WHERE u.Reputation > 1000 
                AND p.PostTypeId = 1 
                AND ph.PostHistoryTypeId = 1 
                AND b.Name IN ('Good Answer', 'Great Answer')
                AND NOT EXISTS (
                    SELECT 1 FROM Posts p2 
                    WHERE p2.OwnerUserId = u.Id 
                    AND p2.PostTypeId = 2 
                    AND COALESCE(p2.Score, 0) < 10
                )
            ) sub) 
    END as ComplexAnalysisResult,
    COUNT(DISTINCT CASE WHENupa.EliteUserFlag = 1 THEN upa.UserId END) as EliteUserCount,
    COUNT(DISTINCT CASE WHEN upa.ReputationTier = 'Grandmaster' THEN upa.UserId END) as GrandmasterCount,
    AVG(upa.AvgQuestionScore) as AvgQuestionScore,
    SUM(upa.Badges) as TotalBadges,
    MAX(upa.NetVotes) as MaxNetVotes,
    MIN(upa.DaysSinceLastPost) as MinDaysSinceLastPost,
    AVG(upa.Reputation) as AvgReputation,
    COUNT(DISTINCT CASE WHEN t.PopularityLevel = 'Popular' THEN t.TagName END) as PopularTagCount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) as ClosedPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
    AVG(CASE WHEN p.AnswerCount > 0 THEN p.AnswerCount ELSE NULL END) as AvgAnswerCount,
    SUM(CASE WHEN p.Score >= 0 THEN p.Score ELSE 0 END) as PositiveScoreTotal,
    COUNT(DISTINCT CASE WHEN p.CreationDate > DATEADD('year', -1, CURRENT_DATE) THEN p.Id END) as RecentPosts,
    COUNT(DISTINCT CASE WHEN u.CreationDate > DATEADD('year', -2, CURRENT_DATE) THEN u.Id END) as RecentUsers,
    (SELECT COUNT(*) FROM (
        SELECT p.Id, COUNT(*) as VoteCount
        FROM Posts p
        INNER JOIN Votes v ON p.Id = v.PostId
        WHERE v.VoteTypeId IN (2, 3)
        GROUP BY p.Id
        HAVING COUNT(*) >= 20
    ) high_voted) as HighlyVotedPosts,
    (SELECT COUNT(*) FROM (
        SELECT u.Id
        FROM Users u
        INNER JOIN Badges b ON u.Id = b.UserId
        WHERE b.Date > DATEADD('month', -6, CURRENT_DATE)
        GROUP BY u.Id
        HAVING COUNT(*) >= 5
    ) recent_badgeholders) as RecentBadgeholders,
    (SELECT AVG(score) FROM (
        SELECT p.Score
        FROM Posts p
        INNER JOIN Users u ON p.OwnerUserId = u.Id
        WHERE u.Reputation >= 1000
        AND p.PostTypeId = 2
        AND p.CreationDate > DATEADD('year', -2, CURRENT_DATE)
    ) recent_answers) as AvgRecentAnswerScore,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<sql>%' AND p.PostTypeId = 1) as SQLQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<python>%' AND p.PostTypeId = 1) as PythonQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<javascript>%' AND p.PostTypeId = 1) as JSQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<java>%' AND p.PostTypeId = 1) as JavaQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<c#>%' AND p.PostTypeId = 1) as CSharpQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<php>%' AND p.PostTypeId = 1) as PHPQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<ruby>%' AND p.PostTypeId = 1) as RubyQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<go>%' AND p.PostTypeId = 1) as GoQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<rust>%' AND p.PostTypeId = 1) as RustQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<cpp>%' AND p.PostTypeId = 1) as CPPQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<c>%' AND p.PostTypeId = 1) as CQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<html>%' AND p.PostTypeId = 1) as HTMLQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%<css>%' AND p.PostTypeId = 1) as CSSQuestions
FROM ComplexUserAnalysis upa
CROSS JOIN Users u
INNER JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
WHERE u.CreationDate >= '2010-01-01'
AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
AND NOT EXISTS (
    SELECT 1 FROM PostHistory ph2 
    WHERE ph2.PostId = p.Id 
    AND ph2.PostHistoryTypeId IN (12, 13) 
    AND ph2.CreationDate > DATEADD('month', -3, CURRENT_DATE)
)
GROUP BY 
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT u.Id 
        FROM Users u 
        INNER JOIN Posts p ON u.Id = p.OwnerUserId 
        INNER JOIN PostHistory ph ON p.Id = ph.PostId 
        INNER JOIN Badges b ON u.Id = b.UserId 
        WHERE u.Reputation > 1000 
        AND p.PostTypeId = 1 
        AND ph.PostHistoryTypeId = 1 
        AND b.Name IN ('Good Answer', 'Great Answer')
        AND NOT EXISTS (
            SELECT 1 FROM Posts p2 
            WHERE p2.OwnerUserId = u.Id 
            AND p2.PostTypeId = 2 
            AND COALESCE(p2.Score, 0) < 10
        )
    ) sub),
    (SELECT COUNT(*) FROM (
        SELECT p.Id, COUNT(*) as VoteCount
        FROM Posts p
        INNER JOIN Votes v ON p.Id = v.PostId
        WHERE v.VoteTypeId IN (2, 3)
        GROUP BY p.Id
        HAVING COUNT(*) >= 20
    ) high_voted),
    (SELECT COUNT(*) FROM (
        SELECT u.Id
        FROM Users u
        INNER JOIN Badges b ON u.Id = b.UserId
        WHERE b.Date > DATEADD('month', -6, CURRENT_DATE)
        GROUP BY u.Id
        HAVING COUNT(*) >= 5
    ) recent_badgeholders),
    (SELECT AVG(score) FROM (
        SELECT p.Score
        FROM Posts p
        INNER JOIN Users u ON p.OwnerUserId = u.Id
        WHERE u.Reputation >= 1000
        AND p.PostTypeId = 2
        AND p.CreationDate > DATEADD('year', -2, CURRENT_DATE)
    ) recent_answers)
HAVING 
    COUNT(DISTINCT CASE WHENupa.EliteUserFlag = 1 THEN upa.UserId END) > 0
    OR COUNT(DISTINCT CASE WHEN upa.ReputationTier = 'Grandmaster' THEN upa.UserId END) > 0
    OR COUNT(DISTINCT CASE WHEN t.PopularityLevel = 'Popular' THEN t.TagName END) > 0
    OR COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) > 0
    OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 1000