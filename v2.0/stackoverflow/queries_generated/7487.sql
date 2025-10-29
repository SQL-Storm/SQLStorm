-- {"query": "7487.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3242} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
    MAX(p.CreationDate) as LatestPostDate,
    MIN(p.CreationDate) as FirstPostDate,
    COUNT(DISTINCT b.Id) as BadgeCount,
    STRING_AGG(DISTINCT b.Name, ', ') as BadgesEarned,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT ph.Id) as EditHistoryCount,
    COUNT(DISTINCT pl.Id) as LinksCount,
    (
        SELECT COUNT(*) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.PostTypeId = 1 
        AND p2.ClosedDate IS NOT NULL
    ) as ClosedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id 
        AND p3.PostTypeId = 2 
        AND p3.ParentId IN (
            SELECT Id 
            FROM Posts p4 
            WHERE p4.OwnerUserId = u.Id 
            AND p4.PostTypeId = 1 
            AND p4.AcceptedAnswerId IS NOT NULL
        )
    ) as AcceptedAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p5 
        WHERE p5.OwnerUserId = u.Id 
        AND p5.PostTypeId = 1 
        AND p5.AnswerCount > 0
    ) as QuestionWithAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p6 
        WHERE p6.OwnerUserId = u.Id 
        AND p6.PostTypeId = 1 
        AND p6.ViewCount > 1000
    ) as HighlyViewedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p7 
        WHERE p7.OwnerUserId = u.Id 
        AND p7.PostTypeId = 1 
        AND p7.ViewCount BETWEEN 100 AND 1000
    ) as ModeratelyViewedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p8 
        WHERE p8.OwnerUserId = u.Id 
        AND p8.PostTypeId = 1 
        AND p8.ViewCount < 100
    ) as LowViewedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p9 
        WHERE p9.OwnerUserId = u.Id 
        AND p9.PostTypeId = 2 
        AND p9.Score > 5
    ) as HighScoringAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p10 
        WHERE p10.OwnerUserId = u.Id 
        AND p10.PostTypeId = 2 
        AND p10.Score <= 5
    ) as LowScoringAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p11 
        WHERE p11.OwnerUserId = u.Id 
        AND p11.PostTypeId = 1 
        AND p11.FavoriteCount > 10
    ) as HighlyFavoritedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p12 
        WHERE p12.OwnerUserId = u.Id 
        AND p12.PostTypeId = 1 
        AND p12.CommentCount > 5
    ) as QuestionWithManyComments,
    (
        SELECT COUNT(*) 
        FROM Posts p13 
        WHERE p13.OwnerUserId = u.Id 
        AND p13.PostTypeId = 2 
        AND p13.CommentCount > 10
    ) as AnswerWithManyComments,
    (
        SELECT COUNT(*) 
        FROM Posts p14 
        WHERE p14.OwnerUserId = u.Id 
        AND p14.PostTypeId = 1 
        AND p14.Tags IS NOT NULL 
        AND LENGTH(p14.Tags) > 0
    ) as TaggedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p15 
        WHERE p15.OwnerUserId = u.Id 
        AND p15.PostTypeId = 1 
        AND p15.Tags IS NULL
    ) as UntaggedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p16 
        WHERE p16.OwnerUserId = u.Id 
        AND p16.PostTypeId = 1 
        AND p16.Title IS NOT NULL 
        AND LENGTH(p16.Title) > 50
    ) as LongTitleQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p17 
        WHERE p17.OwnerUserId = u.Id 
        AND p17.PostTypeId = 1 
        AND p17.Title IS NOT NULL 
        AND LENGTH(p17.Title) <= 50
    ) as ShortTitleQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p18 
        WHERE p18.OwnerUserId = u.Id 
        AND p18.PostTypeId = 1 
        AND p18.ContentLicense = 'CC BY-SA 4.0'
    ) as CCBySaQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p19 
        WHERE p19.OwnerUserId = u.Id 
        AND p19.PostTypeId = 2 
        AND p19.ContentLicense = 'CC BY-SA 4.0'
    ) as CCBySaAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p20 
        WHERE p20.OwnerUserId = u.Id 
        AND p20.PostTypeId = 1 
        AND p20.CommunityOwnedDate IS NOT NULL
    ) as CommunityOwnedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p21 
        WHERE p21.OwnerUserId = u.Id 
        AND p21.PostTypeId = 2 
        AND p21.CommunityOwnedDate IS NOT NULL
    ) as CommunityOwnedAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p22 
        WHERE p22.OwnerUserId = u.Id 
        AND p22.PostTypeId = 1 
        AND p22.LastActivityDate > '2023-01-01'
    ) as RecentlyActiveQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p23 
        WHERE p23.OwnerUserId = u.Id 
        AND p23.PostTypeId = 2 
        AND p23.LastActivityDate > '2023-01-01'
    ) as RecentlyActiveAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p24 
        WHERE p24.OwnerUserId = u.Id 
        AND p24.PostTypeId = 1 
        AND p24.LastActivityDate < '2023-01-01'
    ) as InactiveQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p25 
        WHERE p25.OwnerUserId = u.Id 
        AND p25.PostTypeId = 2 
        AND p25.LastActivityDate < '2023-01-01'
    ) as InactiveAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p26 
        WHERE p26.OwnerUserId = u.Id 
        AND p26.PostTypeId = 1 
        AND p26.CreationDate > '2023-01-01'
    ) as RecentQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p27 
        WHERE p27.OwnerUserId = u.Id 
        AND p27.PostTypeId = 2 
        AND p27.CreationDate > '2023-01-01'
    ) as RecentAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p28 
        WHERE p28.OwnerUserId = u.Id 
        AND p28.PostTypeId = 1 
        AND p28.CreationDate < '2023-01-01'
    ) as OldQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p29 
        WHERE p29.OwnerUserId = u.Id 
        AND p29.PostTypeId = 2 
        AND p29.CreationDate < '2023-01-01'
    ) as OldAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p30 
        WHERE p30.OwnerUserId = u.Id 
        AND p30.PostTypeId = 1 
        AND p30.Score > (
            SELECT AVG(p31.Score) 
            FROM Posts p31 
            WHERE p31.PostTypeId = 1
        )
    ) as AboveAverageQuestionScore,
    (
        SELECT COUNT(*) 
        FROM Posts p32 
        WHERE p32.OwnerUserId = u.Id 
        AND p32.PostTypeId = 2 
        AND p32.Score > (
            SELECT AVG(p33.Score) 
            FROM Posts p33 
            WHERE p33.PostTypeId = 2
        )
    ) as AboveAverageAnswerScore,
    (
        SELECT COUNT(*) 
        FROM Posts p34 
        WHERE p34.OwnerUserId = u.Id 
        AND p34.PostTypeId = 1 
        AND p34.Score < (
            SELECT AVG(p35.Score) 
            FROM Posts p35 
            WHERE p35.PostTypeId = 1
        )
    ) as BelowAverageQuestionScore,
    (
        SELECT COUNT(*) 
        FROM Posts p36 
        WHERE p36.OwnerUserId = u.Id 
        AND p36.PostTypeId = 2 
        AND p36.Score < (
            SELECT AVG(p37.Score) 
            FROM Posts p37 
            WHERE p37.PostTypeId = 2
        )
    ) as BelowAverageAnswerScore,
    (
        SELECT STRING_AGG(DISTINCT t.TagName, ', ')
        FROM Tags t
        INNER JOIN Posts p38 ON p38.Tags LIKE '%' || t.TagName || '%'
        WHERE p38.OwnerUserId = u.Id 
        AND p38.PostTypeId = 1
        AND t.TagName IS NOT NULL
    ) as UserTagsUsed,
    (
        SELECT COUNT(*) 
        FROM Posts p39 
        WHERE p39.OwnerUserId = u.Id 
        AND p39.PostTypeId = 1 
        AND p39.Tags LIKE '%<%'
    ) as QuestionsWithMultipleTags,
    (
        SELECT COUNT(*) 
        FROM Posts p40 
        WHERE p40.OwnerUserId = u.Id 
        AND p40.PostTypeId = 1 
        AND p40.Tags IS NOT NULL 
        AND p40.Tags LIKE '%<%>%' 
        AND LENGTH(p40.Tags) > 50
    ) as QuestionsWithManyTags,
    (
        SELECT COUNT(*) 
        FROM Posts p41 
        WHERE p41.OwnerUserId = u.Id 
        AND p41.PostTypeId = 1 
        AND p41.Title LIKE '%?'
    ) as QuestionsWithQuestionMark,
    (
        SELECT COUNT(*) 
        FROM Posts p42 
        WHERE p42.OwnerUserId = u.Id 
        AND p42.PostTypeId = 1 
        AND p42.Body LIKE '%<%'
    ) as QuestionsWithHtmlTags,
    (
        SELECT COUNT(*) 
        FROM Posts p43 
        WHERE p43.OwnerUserId = u.Id 
        AND p43.PostTypeId = 1 
        AND LENGTH(p43.Body) > 1000
    ) as LongBodyQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p44 
        WHERE p44.OwnerUserId = u.Id 
        AND p44.PostTypeId = 1 
        AND LENGTH(p44.Body) <= 1000
    ) as ShortBodyQuestions,
    (
        SELECT MAX(p45.Score) 
        FROM Posts p45 
        WHERE p45.OwnerUserId = u.Id 
        AND p45.PostTypeId = 1
    ) as MaxQuestionScore,
    (
        SELECT MAX(p46.Score) 
        FROM Posts p46 
        WHERE p46.OwnerUserId = u.Id 
        AND p46.PostTypeId = 2
    ) as MaxAnswerScore,
    (
        SELECT MIN(p47.Score) 
        FROM Posts p47 
        WHERE p47.OwnerUserId = u.Id 
        AND p47.PostTypeId = 1
    ) as MinQuestionScore,
    (
        SELECT MIN(p48.Score) 
        FROM Posts p48 
        WHERE p48.OwnerUserId = u.Id 
        AND p48.PostTypeId = 2
    ) as MinAnswerScore,
    (
        SELECT AVG(p49.Score) 
        FROM Posts p49 
        WHERE p49.OwnerUserId = u.Id 
        AND p49.PostTypeId = 1
    ) as AvgQuestionScoreOverall,
    (
        SELECT AVG(p50.Score) 
        FROM Posts p50 
        WHERE p50.OwnerUserId = u.Id 
        AND p50.PostTypeId = 2
    ) as AvgAnswerScoreOverall,
    (
        SELECT COUNT(DISTINCT p51.OwnerUserId) 
        FROM Posts p51
        WHERE p51.PostTypeId = 1 
        AND p51.AcceptedAnswerId IS NOT NULL
        AND EXISTS (
            SELECT 1 
            FROM Posts p52 
            WHERE p52.Id = p51.AcceptedAnswerId 
            AND p52.OwnerUserId = u.Id
        )
    ) as QuestionsWithAcceptedAnswersFromUser,
    (
        SELECT COUNT(DISTINCT p53.OwnerUserId) 
        FROM Posts p53
        WHERE p53.PostTypeId = 2 
        AND p53.ParentId IN (
            SELECT Id 
            FROM Posts p54 
            WHERE p54.OwnerUserId = u.Id 
            AND p54.PostTypeId = 1
        )
    ) as AnswersToUserQuestions
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN PostHistory ph ON ph.UserId = u.Id
LEFT JOIN PostLinks pl ON pl.PostId IN (
    SELECT Id FROM Posts p55 WHERE p55.OwnerUserId = u.Id
)
WHERE u.Id > 0
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY u.Reputation DESC, TotalPosts DESC
LIMIT 10000;