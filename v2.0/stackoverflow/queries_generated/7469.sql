-- {"query": "7469.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 9060} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) as QuestionCount,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) as AnswerCount,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
    COUNT(DISTINCT b.Id) as BadgeCount,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COALESCE(AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END), 0) as AvgQuestionScore,
    COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0) as AvgAnswerScore,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT ph.Id) as PostHistoryCount,
    COUNT(DISTINCT pl.Id) as PostLinkCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as Downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as FavoriteCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCountWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN p.Id END) as AnswerCountWithParent,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) as QuestionWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id END) as CommunityOwnedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ViewCount > 1000 THEN p.Id END) as HighViewAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 10 THEN p.Id END) as HighlyAnsweredQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score < 0 THEN p.Id END) as NegativeScoreQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score < 0 THEN p.Id END) as NegativeScoreAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND (p.Tags IS NOT NULL AND p.Tags != '') THEN p.Id END) as TaggedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND (p.Tags IS NULL OR p.Tags = '') THEN p.Id END) as UntaggedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.LastActivityDate >= '2020-01-01' THEN p.Id END) as ActiveQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.LastActivityDate >= '2020-01-01' THEN p.Id END) as ActiveAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CreationDate >= '2020-01-01' THEN p.Id END) as NewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CreationDate >= '2020-01-01' THEN p.Id END) as NewAnswers,
    COALESCE(MAX(p.CreationDate), '1900-01-01') as LatestPostDate,
    COALESCE(MIN(p.CreationDate), '9999-12-31') as EarliestPostDate,
    COALESCE(MAX(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate END), '1900-01-01') as LatestQuestionDate,
    COALESCE(MIN(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate END), '9999-12-31') as EarliestQuestionDate,
    COALESCE(MAX(CASE WHEN p.PostTypeId = 2 THEN p.CreationDate END), '1900-01-01') as LatestAnswerDate,
    COALESCE(MIN(CASE WHEN p.PostTypeId = 2 THEN p.CreationDate END), '9999-12-31') as EarliestAnswerDate,
    DATEDIFF('day', COALESCE(MIN(p.CreationDate), '1900-01-01'), COALESCE(MAX(p.CreationDate), '1900-01-01')) as ActiveDays,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS FLOAT) / COUNT(DISTINCT p.Id) * 100, 2) 
        ELSE 0 
    END as QuestionPercentage,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS FLOAT) / COUNT(DISTINCT p.Id) * 100, 2) 
        ELSE 0 
    END as AnswerPercentage,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(CAST(COUNT(DISTINCT b.Id) AS FLOAT) / COUNT(DISTINCT p.Id) * 100, 2) 
        ELSE 0 
    END as BadgePerPostPercentage,
    CASE 
        WHEN AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) > 0 THEN 
            ROUND(CAST(AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS FLOAT), 2) 
        ELSE 0 
    END as AvgQuestionScoreRounded,
    CASE 
        WHEN AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) > 0 THEN 
            ROUND(CAST(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS FLOAT), 2) 
        ELSE 0 
    END as AvgAnswerScoreRounded,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 THEN 
            ROUND(CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score > 0 THEN p.Id END) AS FLOAT) / 
                  COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100, 2) 
        ELSE 0 
    END as PositiveQuestionPercentage,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 THEN 
            ROUND(CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Id END) AS FLOAT) / 
                  COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100, 2) 
        ELSE 0 
    END as PositiveAnswerPercentage,
    COALESCE(ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC), 0) as RankByPostCount,
    COALESCE(RANK() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) DESC), 0) as RankByTotalQuestionScore,
    COALESCE(DENSE_RANK() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) DESC), 0) as RankByTotalAnswerScore,
    COALESCE(FIRST_VALUE(u.Reputation) OVER (ORDER BY u.Reputation DESC ROWS UNBOUNDED PRECEDING), 0) as TopReputation,
    COALESCE(LAST_VALUE(u.Reputation) OVER (ORDER BY u.Reputation ASC ROWS UNBOUNDED PRECEDING), 0) as BottomReputation,
    COALESCE(NTH_VALUE(u.Reputation, 500) OVER (ORDER BY u.Reputation ASC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING), 0) as FiftiethPercentileReputation,
    COALESCE(COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) * 3 + 
             COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) * 2 + 
             COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) * 1, 
             0) as BadgePoints,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) + 
             SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) + 
             COUNT(DISTINCT b.Id) + 
             COUNT(DISTINCT c.Id) + 
             COUNT(DISTINCT ph.Id), 
             0) as TotalActivity,
    COALESCE(ROW_NUMBER() OVER (ORDER BY 
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) + 
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) + 
        COUNT(DISTINCT b.Id) + 
        COUNT(DISTINCT c.Id) + 
        COUNT(DISTINCT ph.Id) DESC), 
        0) as ActivityRank,
    CASE 
        WHEN EXISTS(SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 2 AND p2.Score >= 100) THEN 'Expert' 
        WHEN EXISTS(SELECT 1 FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2 AND p3.Score >= 50) THEN 'Skilled' 
        WHEN EXISTS(SELECT 1 FROM Posts p4 WHERE p4.OwnerUserId = u.Id AND p4.PostTypeId = 2 AND p4.Score >= 10) THEN 'Intermediate' 
        WHEN EXISTS(SELECT 1 FROM Posts p5 WHERE p5.OwnerUserId = u.Id AND p5.PostTypeId = 2) THEN 'Beginner' 
        ELSE 'Newcomer' 
    END as AnswerSkillLevel,
    CASE 
        WHEN EXISTS(SELECT 1 FROM Posts p6 WHERE p6.OwnerUserId = u.Id AND p6.PostTypeId = 1 AND p6.Score >= 100) THEN 'Expert' 
        WHEN EXISTS(SELECT 1 FROM Posts p7 WHERE p7.OwnerUserId = u.Id AND p7.PostTypeId = 1 AND p7.Score >= 50) THEN 'Skilled' 
        WHEN EXISTS(SELECT 1 FROM Posts p8 WHERE p8.OwnerUserId = u.Id AND p8.PostTypeId = 1 AND p8.Score >= 10) THEN 'Intermediate' 
        WHEN EXISTS(SELECT 1 FROM Posts p9 WHERE p9.OwnerUserId = u.Id AND p9.PostTypeId = 1) THEN 'Beginner' 
        ELSE 'Newcomer' 
    END as QuestionSkillLevel,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 
             COALESCE((SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND OwnerUserId = u.Id) * 0.9, 0) THEN 'Consistent' 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 
             COALESCE((SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND OwnerUserId = u.Id) * 0.5, 0) THEN 'Regular' 
        ELSE 'Occasional' 
    END as QuestionFrequency,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 
             COALESCE((SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND OwnerUserId = u.Id) * 0.9, 0) THEN 'Consistent' 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 
             COALESCE((SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND OwnerUserId = u.Id) * 0.5, 0) THEN 'Regular' 
        ELSE 'Occasional' 
    END as AnswerFrequency,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) = 0 AND 
             COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) = 0 THEN 'Inactive' 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 100 OR 
             COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 100 THEN 'Active' 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 10 OR 
             COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 10 THEN 'Moderate' 
        ELSE 'Low' 
    END as ActivityLevel,
    COALESCE(
        (SELECT STRING_AGG(Name, ', ') 
         FROM Badges b2 
         WHERE b2.UserId = u.Id 
           AND b2.Class = 1 
         ORDER BY b2.Date DESC 
         LIMIT 5), 
        'No Gold Badges') as RecentGoldBadges,
    COALESCE(
        (SELECT STRING_AGG(Name, ', ') 
         FROM Badges b3 
         WHERE b3.UserId = u.Id 
           AND b3.Class = 2 
         ORDER BY b3.Date DESC 
         LIMIT 5), 
        'No Silver Badges') as RecentSilverBadges,
    COALESCE(
        (SELECT STRING_AGG(Name, ', ') 
         FROM Badges b4 
         WHERE b4.UserId = u.Id 
           AND b4.Class = 3 
         ORDER BY b4.Date DESC 
         LIMIT 5), 
        'No Bronze Badges') as RecentBronzeBadges,
    COALESCE(
        (SELECT STRING_AGG(DATEDIFF('day', p1.CreationDate, p1.LastActivityDate) AS DaysActive 
         FROM Posts p1 
         WHERE p1.OwnerUserId = u.Id 
           AND p1.PostTypeId = 1 
           AND p1.CreationDate >= '2020-01-01' 
         ORDER BY p1.CreationDate 
         LIMIT 10), 
        'No Data') as QuestionDaysActive,
    COALESCE(
        (SELECT STRING_AGG(DATEDIFF('day', p2.CreationDate, p2.LastActivityDate) AS DaysActive 
         FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id 
           AND p2.PostTypeId = 2 
           AND p2.CreationDate >= '2020-01-01' 
         ORDER BY p2.CreationDate 
         LIMIT 10), 
        'No Data') as AnswerDaysActive,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p3 
         WHERE p3.OwnerUserId = u.Id 
           AND p3.PostTypeId = 1 
           AND p3.CreationDate >= '2020-01-01'
           AND p3.Score > 20), 
        0) as HighScoreQuestions,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p4 
         WHERE p4.OwnerUserId = u.Id 
           AND p4.PostTypeId = 2 
           AND p4.CreationDate >= '2020-01-01'
           AND p4.Score > 20), 
        0) as HighScoreAnswers,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p5 
         WHERE p5.OwnerUserId = u.Id 
           AND p5.PostTypeId = 1 
           AND p5.CreationDate >= '2020-01-01'
           AND p5.ViewCount > 100), 
        0) as HighViewQuestionCount,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p6 
         WHERE p6.OwnerUserId = u.Id 
           AND p6.PostTypeId = 2 
           AND p6.CreationDate >= '2020-01-01'
           AND p6.ViewCount > 100), 
        0) as HighViewAnswerCount,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 THEN 
            ROUND(CAST(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS FLOAT) / 
                  COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 2) 
        ELSE 0 
    END as AvgQuestionScorePerPost,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 THEN 
            ROUND(CAST(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS FLOAT) / 
                  COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END), 2) 
        ELSE 0 
    END as AvgAnswerScorePerPost,
    COALESCE(
        (SELECT COUNT(DISTINCT r1.Id) 
         FROM Posts p7 
         JOIN PostLinks r1 ON r1.PostId = p7.Id 
         WHERE p7.OwnerUserId = u.Id 
           AND r1.LinkTypeId = 1), 
        0) as LinkedQuestionsCount,
    COALESCE(
        (SELECT COUNT(DISTINCT r2.Id) 
         FROM Posts p8 
         JOIN PostLinks r2 ON r2.RelatedPostId = p8.Id 
         WHERE p8.OwnerUserId = u.Id 
           AND r2.LinkTypeId = 1), 
        0) as LinkedAnswersCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount >= 1 THEN p.Id END) as QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount >= 5 THEN p.Id END) as HighlyAnsweredQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score > 0 THEN p.Id END) as PositiveScoringQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Id END) as PositiveScoringAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 0 THEN p.Id END) as ViewedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ViewCount > 0 THEN p.Id END) as ViewedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) as CommentedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CommentCount > 0 THEN p.Id END) as CommentedAnswers,
    COALESCE(
        (SELECT AVG(p9.Score) 
         FROM Posts p9 
         WHERE p9.OwnerUserId = u.Id 
           AND p9.PostTypeId = 1), 
        0) as AvgOwnQuestionScore,
    COALESCE(
        (SELECT AVG(p10.Score) 
         FROM Posts p10 
         WHERE p10.OwnerUserId = u.Id 
           AND p10.PostTypeId = 2), 
        0) as AvgOwnAnswerScore,
    COALESCE(
        (SELECT AVG(p11.Score) 
         FROM Posts p11 
         WHERE p11.OwnerUserId = u.Id 
           AND p11.PostTypeId = 1 
           AND p11.CreationDate >= '2020-01-01'), 
        0) as AvgRecentQuestionScore,
    COALESCE(
        (SELECT AVG(p12.Score) 
         FROM Posts p12 
         WHERE p12.OwnerUserId = u.Id 
           AND p12.PostTypeId = 2 
           AND p12.CreationDate >= '2020-01-01'), 
        0) as AvgRecentAnswerScore,
    COALESCE(
        (SELECT AVG(p13.Score) 
         FROM Posts p13 
         WHERE p13.OwnerUserId = u.Id 
           AND p13.PostTypeId = 1 
           AND p13.LastActivityDate >= '2020-01-01'), 
        0) as AvgActiveQuestionScore,
    COALESCE(
        (SELECT AVG(p14.Score) 
         FROM Posts p14 
         WHERE p14.OwnerUserId = u.Id 
           AND p14.PostTypeId = 2 
           AND p14.LastActivityDate >= '2020-01-01'), 
        0) as AvgActiveAnswerScore,
    COALESCE(
        (SELECT COUNT(DISTINCT v1.Id) 
         FROM Votes v1 
         WHERE v1.UserId = u.Id 
           AND v1.VoteTypeId = 2), 
        0) as TotalUpvotes,
    COALESCE(
        (SELECT COUNT(DISTINCT v2.Id) 
         FROM Votes v2 
         WHERE v2.UserId = u.Id 
           AND v2.VoteTypeId = 3), 
        0) as TotalDownvotes,
    COALESCE(
        (SELECT COUNT(DISTINCT p15.Id) 
         FROM Posts p15 
         JOIN Votes v3 ON v3.PostId = p15.Id 
         WHERE v3.UserId = u.Id 
           AND v3.VoteTypeId = 2 
           AND p15.OwnerUserId = u.Id), 
        0) as UpvotedOwnPosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p16.Id) 
         FROM Posts p16 
         JOIN Votes v4 ON v4.PostId = p16.Id 
         WHERE v4.UserId = u.Id 
           AND v4.VoteTypeId = 3 
           AND p16.OwnerUserId = u.Id), 
        0) as DownvotedOwnPosts,
    COALESCE(
        (SELECT STRING_AGG(p17.Title, ' | ') 
         FROM Posts p17 
         WHERE p17.OwnerUserId = u.Id 
           AND p17.PostTypeId = 1 
           AND p17.CreationDate >= '2020-01-01' 
         ORDER BY p17.CreationDate DESC 
         LIMIT 10), 
        'No Recent Questions') as RecentQuestionTitles,
    COALESCE(
        (SELECT STRING_AGG(p18.Body, ' | ') 
         FROM Posts p18 
         WHERE p18.OwnerUserId = u.Id 
           AND p18.PostTypeId = 2 
           AND p18.CreationDate >= '2020-01-01' 
         ORDER BY p18.CreationDate DESC 
         LIMIT 10), 
        'No Recent Answers') as RecentAnswerBodies,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p19 
         WHERE p19.OwnerUserId = u.Id 
           AND p19.PostTypeId = 1 
           AND p19.CreationDate >= '2020-01-01' 
           AND p19.Score > (SELECT AVG(p20.Score) FROM Posts p20 WHERE p20.PostTypeId = 1)), 
        0) as AboveAvgScoreQuestions,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p21 
         WHERE p21.OwnerUserId = u.Id 
           AND p21.PostTypeId = 2 
           AND p21.CreationDate >= '2020-01-01' 
           AND p21.Score > (SELECT AVG(p22.Score) FROM Posts p22 WHERE p22.PostTypeId = 2)), 
        0) as AboveAvgScoreAnswers,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p23 
         WHERE p23.OwnerUserId = u.Id 
           AND p23.PostTypeId = 1 
           AND p23.ViewCount > (SELECT AVG(p24.ViewCount) FROM Posts p24 WHERE p24.PostTypeId = 1)), 
        0) as AboveAvgViewedQuestions,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p25 
         WHERE p25.OwnerUserId = u.Id 
           AND p25.PostTypeId = 2 
           AND p25.ViewCount > (SELECT AVG(p26.ViewCount) FROM Posts p26 WHERE p26.PostTypeId = 2)), 
        0) as AboveAvgViewedAnswers,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Badges b5 
         WHERE b5.UserId = u.Id 
           AND b5.Date >= '2020-01-01'), 
        0) as RecentBadgesCount,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Comments c1 
         WHERE c1.UserId = u.Id 
           AND c1.CreationDate >= '2020-01-01'), 
        0) as RecentCommentsCount,
    COALESCE(
        (SELECT COUNT(*) 
         FROM PostHistory ph1 
         WHERE ph1.UserId = u.Id 
           AND ph1.CreationDate >= '2020-01-01'), 
        0) as RecentPostHistoryCount,
    COALESCE(
        (SELECT COUNT(*) 
         FROM PostLinks pl1 
         WHERE pl1.Id IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) 
           AND pl1.CreationDate >= '2020-01-01'), 
        0) as RecentPostLinksCount,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v5 
         WHERE v5.UserId = u.Id 
           AND v5.CreationDate >= '2020-01-01'), 
        0) as RecentVotesCount,
    COALESCE(
        (SELECT STRING_AGG(CONCAT('Q:', p27.Id, ':', p27.Score, ':', p27.ViewCount, ':', p27.AnswerCount), '|') 
         FROM Posts p27 
         WHERE p27.OwnerUserId = u.Id 
           AND p27.PostTypeId = 1 
           AND p27.CreationDate >= '2020-01-01' 
           AND (p27.Score > 0 OR p27.ViewCount > 50 OR p27.AnswerCount > 0) 
         ORDER BY p27.CreationDate DESC 
         LIMIT 5), 
        'No Significant Questions') as SignificantQuestions,
    COALESCE(
        (SELECT STRING_AGG(CONCAT('A:', p28.Id, ':', p28.Score, ':', p28.ViewCount), '|') 
         FROM Posts p28 
         WHERE p28.OwnerUserId = u.Id 
           AND p28.PostTypeId = 2 
           AND p28.CreationDate >= '2020-01-01' 
           AND (p28.Score > 0 OR p28.ViewCount > 50) 
         ORDER BY p28.CreationDate DESC 
         LIMIT 5), 
        'No Significant Answers') as SignificantAnswers,
    COALESCE(
        (SELECT STRING_AGG(CONCAT(b6.Name, ':', b6.Date, ':', b6.Class), '|') 
         FROM Badges b6 
         WHERE b6.UserId = u.Id 
           AND b6.Date >= '2020-01-01' 
         ORDER BY b6.Date DESC 
         LIMIT 10), 
        'No Recent Badges') as RecentBadges,
    COALESCE(
        (SELECT STRING_AGG(CONCAT(c2.Text, ' (', c2.CreationDate, ')'), ' || ') 
         FROM Comments c2 
         WHERE c2.UserId = u.Id 
           AND c2.CreationDate >= '2020-01-01' 
         ORDER BY c2.CreationDate DESC 
         LIMIT 10), 
        'No Recent Comments') as RecentComments,
    COALESCE(
        (SELECT STRING_AGG(CONCAT(ph2.PostHistoryTypeId, ':', ph2.CreationDate, ':', ph2.Comment), '|') 
         FROM PostHistory ph2 
         WHERE ph2.UserId = u.Id 
           AND ph2.CreationDate >= '2020-01-01' 
         ORDER BY ph2.CreationDate DESC 
         LIMIT 10), 
        'No Recent History') as RecentHistory,
    COALESCE(
        (SELECT STRING_AGG(CONCAT(pl2.LinkTypeId, ':', pl2.CreationDate), '|') 
         FROM PostLinks pl2 
         WHERE pl2.Id IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) 
           AND pl2.CreationDate >= '2020-01-01' 
         ORDER BY pl2.CreationDate DESC 
         LIMIT 10), 
        'No Recent Links') as RecentLinks,
    COALESCE(
        (SELECT STRING_AGG(CONCAT(v6.VoteTypeId, ':', v6.CreationDate, ':', v6.PostId), '|') 
         FROM Votes v6 
         WHERE v6.UserId = u.Id 
           AND v6.CreationDate >= '2020-01-01' 
         ORDER BY v6.CreationDate DESC 
         LIMIT 10), 
        'No Recent Votes') as RecentVotes,
    COALESCE(
        (SELECT COUNT(DISTINCT p29.Id) 
         FROM Posts p29 
         JOIN Votes v7 ON v7.PostId = p29.Id 
         WHERE p29.OwnerUserId = u.Id 
           AND v7.UserId = u.Id 
           AND v7.VoteTypeId IN (2,3) 
           AND p29.CreationDate >= '2020-01-01'), 
        0) as RecentVotedPosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p30.Id) 
         FROM Posts p30 
         JOIN Votes v8 ON v8.PostId = p30.Id 
         WHERE p30.OwnerUserId = u.Id 
           AND v8.UserId = u.Id 
           AND v8.VoteTypeId IN (2,3) 
           AND p30.CreationDate >= '2020-01-01' 
           AND p30.Score > 0), 
        0) as RecentPositiveVotedPosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p31.Id) 
         FROM Posts p31 
         JOIN Votes v9 ON v9.PostId = p31.Id 
         WHERE p31.OwnerUserId = u.Id 
           AND v9.UserId = u.Id 
           AND v9.VoteTypeId IN (2,3) 
           AND p31.CreationDate >= '2020-01-01' 
           AND p31.Score < 0), 
        0) as RecentNegativeVotedPosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p32.Id) 
         FROM Posts p32 
         JOIN Votes v10 ON v10.PostId = p32.Id 
         WHERE p32.OwnerUserId = u.Id 
           AND v10.UserId = u.Id 
           AND v10.VoteTypeId IN (2,3) 
           AND p32.CreationDate >= '2020-01-01' 
           AND p32.AnswerCount > 0), 
        0) as RecentAnsweredVotedPosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p33.Id) 
         FROM Posts p33 
         JOIN Votes v11 ON v11.PostId = p33.Id 
         WHERE p33.OwnerUserId = u.Id 
           AND v11.UserId = u.Id 
           AND v11.VoteTypeId IN (2,3) 
           AND p33.CreationDate >= '2020-01-01' 
           AND p33.ViewCount > 100), 
        0) as RecentHighViewedVotedPosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p34.Id) 
         FROM Posts p34 
         JOIN Votes v12 ON v12.PostId = p34.Id 
         WHERE p34.OwnerUserId = u.Id 
           AND v12.UserId = u.Id 
           AND v12.VoteTypeId IN (2,3) 
           AND p34.CreationDate >= '2020-01-01' 
           AND p34.Score BETWEEN 1 AND 10), 
        0) as RecentMediumScoreVotedPosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p35.Id) 
         FROM Posts p35 
         JOIN Votes v13 ON v13.PostId = p35.Id 
         WHERE p35.OwnerUserId = u.Id 
           AND v13.UserId = u.Id 
           AND v13.VoteTypeId IN (2,3) 
           AND p35.CreationDate >= '2020-01-01' 
           AND p35.Score BETWEEN 11 AND 100), 
        0) as RecentHighScoreVotedPosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p36.Id) 
         FROM Posts p36 
         WHERE p36.OwnerUserId = u.Id 
           AND p36.PostTypeId = 1 
           AND p36.CreationDate BETWEEN '2020-01-01' AND '2020-12-31' 
           AND p36.Score > 0), 
        0) as Year2020PositiveQuestions,
    COALESCE(
        (SELECT COUNT(DISTINCT p37.Id) 
         FROM Posts p37 
         WHERE p37.OwnerUserId = u.Id 
           AND p37.PostTypeId = 2 
           AND p37.CreationDate BETWEEN '2020-01-01' AND '2020-12-31' 
           AND p37.Score > 0), 
        0) as Year2020PositiveAnswers,
    COALESCE(
        (SELECT COUNT(DISTINCT p38.Id) 
         FROM Posts p38 
         JOIN Votes v14 ON v14.PostId = p38.Id 
         WHERE p38.OwnerUserId = u.Id 
           AND v14.UserId = u.Id 
           AND v14.VoteTypeId IN (2,3) 
           AND p38.CreationDate BETWEEN '2020-01-01' AND '2020-12-31' 
           AND p38.Score > 0), 
        0) as Year2020PositiveVotedPosts,
    COALESCE(
        (SELECT COUNT(DISTINCT p39.Id) 
         FROM Posts p39 
         WHERE p39.OwnerUserId = u.Id 
           AND p39.PostTypeId = 1 
           AND p39.CreationDate BETWEEN '2020-01-01' AND '2020-12-31' 
           AND p39.ViewCount > 100), 
        0) as Year2020HighViewQuestions,
    COALESCE(
        (SELECT COUNT(DISTINCT p40.Id) 
         FROM Posts p40 
         WHERE p40.OwnerUserId = u.Id 
           AND p40.PostTypeId = 2 
           AND p40.CreationDate BETWEEN '2020-01-01' AND '2020-12-31' 
           AND p40.ViewCount > 100), 
        0) as Year2020HighViewAnswers,
    COALESCE(
        (SELECT COUNT(DISTINCT p41.Id) 
         FROM Posts p41 
         JOIN Badges b7 ON b7.UserId = u.Id 
         WHERE p41.OwnerUserId = u.Id 
           AND p41.PostTypeId = 1 
           AND b7.Date BETWEEN '2020-01-01' AND '2020-12-31' 
           AND b7.Class = 1), 
        0) as Year2020GoldBadgedQuestions,
    COALESCE(
        (SELECT COUNT(DISTINCT p42.Id) 
         FROM Posts p42 
         JOIN Badges b8 ON b8.UserId = u.Id 
         WHERE p42.OwnerUserId = u.Id 
           AND p42.PostTypeId = 2 
           AND b8.Date BETWEEN '2020-01-01' AND '2020-12-31' 
           AND b8.Class = 1), 
        0) as Year2020GoldBadgedAnswers,
    CASE 
        WHEN COUNT(DISTINCT p.Id) = 0 THEN 'New User' 
        WHEN COUNT(DISTINCT p.Id) < 10 THEN 'Occasional User' 
        WHEN COUNT(DISTINCT p.Id) < 50 THEN 'Regular User' 
        WHEN COUNT(DISTINCT p.Id) < 200 THEN 'Active User' 
        WHEN COUNT(DISTINCT p.Id) < 500 THEN 'Highly Active User' 
        ELSE 'Veteran User' 
    END as UserStatus,
    COALESCE(
        (SELECT COUNT(DISTINCT p43.Id) 
         FROM Posts p43 
         WHERE p43.OwnerUserId = u.Id 
           AND p43.PostTypeId = 1 
           AND p43.CreationDate >= '2020-01-01' 
           AND p43.AnswerCount > 0), 
        0) as QuestionWithAnswers2020,
    COALESCE(
        (SELECT COUNT(DISTINCT p44.Id) 
         FROM Posts p44 
         WHERE p44.OwnerUserId = u.Id 
           AND p44.PostTypeId = 2 
           AND p44.CreationDate >= '2020-01-01' 
           AND p44.ViewCount > 1000), 
        0) as HighViewAnswer2020,
    COALESCE(
        (SELECT COUNT(DISTINCT p45.Id) 
         FROM Posts p45 
         WHERE p45.OwnerUserId = u.Id 
           AND p45.PostTypeId = 1 
           AND p45.CreationDate >= '2020-01-01' 
           AND p45.ViewCount > 1000), 
        0) as HighViewQuestion2020,
    COALESCE(
        (SELECT COUNT(DISTINCT p46.Id) 
         FROM Posts p46 
         JOIN Votes v15 ON v15.PostId = p46.Id 
         WHERE p46.OwnerUserId = u.Id 
           AND v15.UserId = u.Id 
           AND v15.VoteTypeId IN (2,3) 
           AND p46.CreationDate >= '2020-01-01' 
           AND p46.Score BETWEEN 0 AND 5), 
        0) as RecentLowScoreVotedPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) + 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) + 
    COUNT(DISTINCT b.Id) + 
    COUNT(DISTINCT c.Id) + 
    COUNT(DISTINCT ph.Id) + 
    COUNT(DISTINCT pl.Id) + 
    COUNT(DISTINCT v.Id) as TotalContributions
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON pl.Id IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
LEFT JOIN Votes v ON u.Id = v.UserId
WHERE u.Id = 12345
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY TotalContributions DESC
LIMIT 100;