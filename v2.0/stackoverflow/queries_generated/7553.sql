-- {"query": "7553.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1868} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswer,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Id END) AS HighScoringAnswers,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
    MAX(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS MaxAnswerScore,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) AS QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) AS QuestionsWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CommentCount > 0 THEN p.Id END) AS AnswerWithComments,
    COUNT(DISTINCT b.Id) AS BadgesCount,
    STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name) AS BadgeNames,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT ph.Id) AS PostHistoryCount,
    COUNT(DISTINCT pl.Id) AS PostLinkCount,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS FavoriteCount,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END), 0) AS TotalBountyAmount,
    MAX(p.CreationDate) AS LatestPostDate,
    MIN(p.CreationDate) AS FirstPostDate,
    DATEDIFF(DAY, MIN(p.CreationDate), MAX(p.CreationDate)) AS ActiveDays,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        THEN CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS FLOAT) / 
             CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS FLOAT)
        ELSE 0 
    END AS AnswersPerQuestion,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) = 0 
        THEN 0 
        ELSE AVG(CAST(p.AnswerCount AS FLOAT)) 
    END AS AvgAnswersPerQuestion,
    STRING_AGG(
        CASE 
            WHEN p.PostTypeId = 1 AND p.Title IS NOT NULL AND LENGTH(p.Title) > 0 
            THEN LEFT(p.Title, 50) + '...' 
            ELSE NULL 
        END, 
        '; ' 
        ORDER BY p.CreationDate DESC
    ) AS RecentTitles,
    COALESCE(
        (SELECT TOP 1 p2.Title 
         FROM Posts p2 
         WHERE p2.PostTypeId = 1 
         AND p2.OwnerUserId = u.Id 
         AND p2.CreationDate = (
             SELECT MAX(p3.CreationDate) 
             FROM Posts p3 
             WHERE p3.PostTypeId = 1 
             AND p3.OwnerUserId = u.Id
         )), 
        'No Questions'
    ) AS LatestQuestionTitle,
    COALESCE(
        (SELECT TOP 1 p4.Title 
         FROM Posts p4 
         WHERE p4.PostTypeId = 2 
         AND p4.OwnerUserId = u.Id 
         AND p4.CreationDate = (
             SELECT MAX(p5.CreationDate) 
             FROM Posts p5 
             WHERE p5.PostTypeId = 2 
             AND p5.OwnerUserId = u.Id
         )), 
        'No Answers'
    ) AS LatestAnswerTitle,
    COALESCE(SUM(p.Score), 0) AS TotalScore,
    COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) AS PositiveScorePosts,
    COUNT(DISTINCT CASE WHEN p.Score < 0 THEN p.Id END) AS NegativeScorePosts,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        THEN ROUND(
            CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Id END) AS FLOAT) * 100.0 / 
            CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS FLOAT), 2
        )
        ELSE 0 
    END AS AnswerSuccessRate,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 1 AND 
             p.Score > (SELECT AVG(p1.Score) FROM Posts p1 WHERE p1.PostTypeId = 1) 
        THEN p.Id 
    END) AS AboveAvgScoreQuestions,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 2 AND 
             p.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 2) 
        THEN p.Id 
    END) AS AboveAvgScoreAnswers,
    COALESCE(
        (SELECT STRING_AGG(
            CASE 
                WHEN LENGTH(pt.Name) > 0 THEN pt.Name 
                ELSE 'Unknown' 
            END, 
            ', '
        ) 
        FROM Posts p6
        INNER JOIN PostTypes pt ON p6.PostTypeId = pt.Id
        WHERE p6.OwnerUserId = u.Id
        GROUP BY p6.OwnerUserId
        ), 
        'No Posts'
    ) AS PostTypes,
    COUNT(DISTINCT CASE 
        WHEN p.CreationDate >= DATEADD(MONTH, -1, GETDATE()) 
        THEN p.Id 
    END) AS PostsLastMonth,
    COALESCE(
        (SELECT TOP 1 p7.Title 
         FROM Posts p7 
         WHERE p7.OwnerUserId = u.Id 
         AND p7.PostTypeId = 1 
         AND p7.Score = (
             SELECT MAX(p8.Score) 
             FROM Posts p8 
             WHERE p8.OwnerUserId = u.Id 
             AND p8.PostTypeId = 1
         )), 
        'No Top Question'
    ) AS TopScoredQuestion,
    COALESCE(
        (SELECT TOP 1 p9.Title 
         FROM Posts p9 
         WHERE p9.OwnerUserId = u.Id 
         AND p9.PostTypeId = 2 
         AND p9.Score = (
             SELECT MAX(p10.Score) 
             FROM Posts p10 
             WHERE p10.OwnerUserId = u.Id 
             AND p10.PostTypeId = 2
         )), 
        'No Top Answer'
    ) AS TopScoredAnswer,
    COUNT(DISTINCT CASE 
        WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) AND ph.CreationDate >= DATEADD(MONTH, -3, GETDATE()) 
        THEN ph.Id 
    END) AS RecentModActions,
    COUNT(DISTINCT CASE 
        WHEN LENGTH(p.Tags) > 0 AND p.Tags NOT LIKE '%<>%' AND p.Tags NOT LIKE '%<%' OR p.Tags LIKE '%<%>%' 
        THEN p.Id 
    END) AS TaggedPosts,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 1 AND p.ViewCount > (SELECT AVG(p11.ViewCount) FROM Posts p11 WHERE p11.PostTypeId = 1) 
        THEN p.Id 
    END) AS AboveAvgViewQuestions
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.RelatedPostId
LEFT JOIN Votes v ON u.Id = v.UserId
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 0
ORDER BY 
    TotalScore DESC,
    RepScore DESC,
    ActiveDays DESC;