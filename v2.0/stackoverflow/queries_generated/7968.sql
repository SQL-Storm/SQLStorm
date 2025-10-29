-- {"query": "7968.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3146} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COALESCE(SUM(p.Score), 0) AS TotalScore,
    COALESCE(AVG(p.Score), 0) AS AverageScore,
    COUNT(DISTINCT b.Id) AS Badges,
    STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames,
    COALESCE(MAX(p.CreationDate), '1900-01-01') AS LatestPostDate,
    COALESCE(MIN(p.CreationDate), '1900-01-01') AS EarliestPostDate,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) AS ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND EXISTS (
        SELECT 1 FROM Votes v 
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2
    ) THEN p.Id END) AS AnsweredWithUpvotes,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND EXISTS (
        SELECT 1 FROM Posts p2 
        WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2
    ) THEN p.Id END) AS QuestionsWithAnswers,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 1 THEN 
            CASE 
                WHEN p.ViewCount > 1000 THEN 'High View'
                WHEN p.ViewCount > 100 THEN 'Medium View'
                ELSE 'Low View'
            END
        ELSE NULL
    END) AS ViewCategoryCount,
    COUNT(DISTINCT CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN p.Id END) AS TaggedPosts,
    COUNT(DISTINCT CASE WHEN p.Tags LIKE '%java%' THEN p.Id END) AS JavaPosts,
    COUNT(DISTINCT CASE WHEN p.Tags LIKE '%python%' THEN p.Id END) AS PythonPosts,
    COUNT(DISTINCT CASE WHEN p.Tags LIKE '%c++%' THEN p.Id END) AS CppPosts,
    COUNT(DISTINCT CASE 
        WHEN p.Tags IS NOT NULL 
        AND p.Tags LIKE '%<java>%' 
        AND p.Tags LIKE '%<python>%' 
        AND p.Tags LIKE '%<c++>%' 
        THEN p.Id 
    END) AS MultiLanguagePosts,
    COUNT(DISTINCT CASE 
        WHEN p.Tags IS NOT NULL 
        AND p.Tags NOT LIKE '%<java>%' 
        AND p.Tags NOT LIKE '%<python>%' 
        AND p.Tags NOT LIKE '%<c++>%' 
        AND LENGTH(p.Tags) > 2 
        THEN p.Id 
    END) AS OtherLanguagePosts,
    COALESCE(SUM(CASE 
        WHEN p.PostTypeId = 1 THEN p.ViewCount 
        ELSE 0 
    END), 0) AS TotalQuestionViews,
    COALESCE(SUM(CASE 
        WHEN p.PostTypeId = 2 THEN p.ViewCount 
        ELSE 0 
    END), 0) AS TotalAnswerViews,
    COALESCE(AVG(CASE 
        WHEN p.PostTypeId = 1 THEN p.ViewCount 
        ELSE NULL 
    END), 0) AS AverageQuestionViews,
    COALESCE(AVG(CASE 
        WHEN p.PostTypeId = 2 THEN p.ViewCount 
        ELSE NULL 
    END), 0) AS AverageAnswerViews,
    COUNT(DISTINCT CASE 
        WHEN EXISTS (
            SELECT 1 FROM Posts p3 
            WHERE p3.ParentId = p.Id 
            AND p3.PostTypeId = 2 
            AND p3.Score > (SELECT AVG(p4.Score) FROM Posts p4 WHERE p4.PostTypeId = 2)
        ) THEN p.Id 
    END) AS QuestionsWithAboveAvgAnswers,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 1 
        AND EXISTS (
            SELECT 1 FROM Posts p5 
            WHERE p5.ParentId = p.Id 
            AND p5.PostTypeId = 2 
            AND p5.Score = (SELECT MAX(p6.Score) FROM Posts p6 WHERE p6.PostTypeId = 2 AND p6.ParentId = p.Id)
        ) THEN p.Id 
    END) AS QuestionsWithHighestRatedAnswers,
    DENSE_RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) AS ReputationRank,
    FIRST_VALUE(u.DisplayName) OVER (
        PARTITION BY u.Reputation 
        ORDER BY COALESCE(SUM(p.Score), 0) DESC
    ) AS BestUserWithSameReputation,
    PERCENT_RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0)) AS ScorePercentile,
    RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank,
    ROW_NUMBER() OVER (ORDER BY u.CreationDate, COALESCE(SUM(p.Score), 0) DESC) AS MembershipOrder,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 10 
        AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 10 
        AND COALESCE(SUM(p.Score), 0) > 1000 
        THEN 'Elite Contributor' 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 5 
        AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 5 
        AND COALESCE(SUM(p.Score), 0) > 500 
        THEN 'Active Contributor' 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 'Regular Contributor' 
        ELSE 'New User' 
    END AS ContributionLevel,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p7 
         WHERE p7.OwnerUserId = u.Id 
         AND p7.PostTypeId = 1 
         AND p7.CreationDate >= DATEADD(YEAR, -1, GETDATE())
        ), 0
    ) AS RecentQuestions,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p8 
         WHERE p8.OwnerUserId = u.Id 
         AND p8.PostTypeId = 2 
         AND p8.CreationDate >= DATEADD(YEAR, -1, GETDATE())
        ), 0
    ) AS RecentAnswers,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p9 
         WHERE p9.OwnerUserId = u.Id 
         AND p9.PostTypeId IN (1,2) 
         AND p9.CreationDate >= DATEADD(MONTH, -3, GETDATE())
        ), 0
    ) AS RecentActivity,
    CASE 
        WHEN COALESCE(AVG(p.Score), 0) > 50 
        AND COALESCE(SUM(p.Score), 0) > 1000 
        AND COUNT(DISTINCT b.Id) > 5 
        THEN 1 
        ELSE 0 
    END AS HighPerformingUser,
    ABS(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) - 
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END)) AS QuestionAnswerRatio,
    COALESCE(
        (SELECT AVG(p10.Score) 
         FROM Posts p10 
         WHERE p10.OwnerUserId = u.Id 
         AND p10.PostTypeId = 1
        ), 0
    ) AS AvgQuestionScore,
    COALESCE(
        (SELECT AVG(p11.Score) 
         FROM Posts p11 
         WHERE p11.OwnerUserId = u.Id 
         AND p11.PostTypeId = 2
        ), 0
    ) AS AvgAnswerScore,
    COALESCE(
        (SELECT COUNT(DISTINCT p12.Id) 
         FROM Posts p12 
         WHERE p12.OwnerUserId = u.Id 
         AND p12.AcceptedAnswerId IS NOT NULL
        ), 0
    ) AS AcceptedAnswers,
    COALESCE(
        (SELECT COUNT(DISTINCT p13.Id) 
         FROM Posts p13 
         WHERE p13.OwnerUserId = u.Id 
         AND p13.CommentCount > 0
        ), 0
    ) AS CommentedPosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p14.Id) 
         FROM Posts p14 
         WHERE p14.OwnerUserId = u.Id 
         AND p14.FavoriteCount > 0
        ), 0
    ) AS FavoritedPosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p15.Id) 
         FROM Posts p15 
         WHERE p15.OwnerUserId = u.Id 
         AND p15.Tags IS NOT NULL 
         AND p15.Tags != ''
        ), 0
    ) AS TaggedPostsCount,
    COALESCE(
        (SELECT COUNT(DISTINCT p16.Id) 
         FROM Posts p16 
         WHERE p16.OwnerUserId = u.Id 
         AND p16.PostTypeId = 1
         AND p16.ViewCount > 1000
        ), 0
    ) AS HighViewQuestions,
    COALESCE(
        (SELECT COUNT(DISTINCT p17.Id) 
         FROM Posts p17 
         WHERE p17.OwnerUserId = u.Id 
         AND p17.PostTypeId = 2
         AND p17.ViewCount > 100
        ), 0
    ) AS HighViewAnswers,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) = 0 
        AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) = 0 
        THEN 'Inactive'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) = 0 
        THEN 'Question Only'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) = 0 
        AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 
        THEN 'Answer Only'
        ELSE 'Mixed'
    END AS PostingStyle,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS UserRankByReputation,
    COALESCE(
        (SELECT COUNT(DISTINCT p18.Id) 
         FROM Posts p18 
         WHERE p18.OwnerUserId = u.Id 
         AND p18.PostTypeId = 1
         AND p18.CreationDate >= DATEADD(MONTH, -6, GETDATE())
        ), 0
    ) AS RecentQuestionCount,
    COALESCE(
        (SELECT COUNT(DISTINCT p19.Id) 
         FROM Posts p19 
         WHERE p19.OwnerUserId = u.Id 
         AND p19.PostTypeId = 2
         AND p19.CreationDate >= DATEADD(MONTH, -6, GETDATE())
        ), 0
    ) AS RecentAnswerCount,
    COALESCE(
        (SELECT COUNT(DISTINCT p20.Id) 
         FROM Posts p20 
         WHERE p20.OwnerUserId = u.Id 
         AND p20.PostTypeId = 1
         AND p20.CreationDate >= DATEADD(WEEK, -2, GETDATE())
        ), 0
    ) AS RecentWeeklyQuestions,
    COALESCE(
        (SELECT COUNT(DISTINCT p21.Id) 
         FROM Posts p21 
         WHERE p21.OwnerUserId = u.Id 
         AND p21.PostTypeId = 2
         AND p21.CreationDate >= DATEADD(WEEK, -2, GETDATE())
        ), 0
    ) AS RecentWeeklyAnswers,
    COALESCE(
        (SELECT STRING_AGG(b2.Name, ', ') 
         FROM Badges b2 
         WHERE b2.UserId = u.Id 
         AND b2.Class = 1
        ), ''
    ) AS GoldBadges,
    COALESCE(
        (SELECT STRING_AGG(b3.Name, ', ') 
         FROM Badges b3 
         WHERE b3.UserId = u.Id 
         AND b3.Class = 2
        ), ''
    ) AS SilverBadges,
    COALESCE(
        (SELECT STRING_AGG(b4.Name, ', ') 
         FROM Badges b4 
         WHERE b4.UserId = u.Id 
         AND b4.Class = 3
        ), ''
    ) AS BronzeBadges,
    COALESCE(
        (SELECT COUNT(DISTINCT p22.Id) 
         FROM Posts p22 
         WHERE p22.OwnerUserId = u.Id 
         AND p22.Score >= 100
        ), 0
    ) AS HighScorePosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p23.Id) 
         FROM Posts p23 
         WHERE p23.OwnerUserId = u.Id 
         AND p23.Score >= 50
        ), 0
    ) AS MediumScorePosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p24.Id) 
         FROM Posts p24 
         WHERE p24.OwnerUserId = u.Id 
         AND p24.Score >= 10
        ), 0
    ) AS LowScorePosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p25.Id) 
         FROM Posts p25 
         WHERE p25.OwnerUserId = u.Id 
         AND p25.Score < 0
        ), 0
    ) AS NegativeScorePosts
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
WHERE u.Id > 0
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY COALESCE(SUM(p.Score), 0) DESC, COUNT(DISTINCT p.Id) DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;