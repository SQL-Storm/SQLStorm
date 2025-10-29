-- {"query": "7212.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 7822} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
    COUNT(DISTINCT b.Id) as BadgesCount,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COUNT(DISTINCT c.Id) as CommentsCount,
    COUNT(DISTINCT v.Id) as VotesCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as FavoriteVotes,
    COUNT(DISTINCT ph.Id) as PostHistoryCount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 4) THEN ph.Id END) as TitleEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN ph.Id END) as BodyEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (3, 6) THEN ph.Id END) as TagEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.Id END) as CloseReopenActions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (12, 13) THEN ph.Id END) as DeleteUndeleteActions,
    MAX(p.CreationDate) as LastPostDate,
    MAX(u.LastAccessDate) as LastAccessDate,
    MAX(ph.CreationDate) as LastHistoryAction,
    (
        SELECT COUNT(*) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.PostTypeId = 1 
        AND p2.CreationDate >= DATEADD(day, -30, GETDATE())
    ) as QuestionsLast30Days,
    (
        SELECT COUNT(*) 
        FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id 
        AND p3.PostTypeId = 2 
        AND p3.CreationDate >= DATEADD(day, -30, GETDATE())
    ) as AnswersLast30Days,
    (
        SELECT COUNT(*) 
        FROM Votes v2 
        WHERE v2.UserId = u.Id 
        AND v2.VoteTypeId = 5 
        AND v2.CreationDate >= DATEADD(day, -30, GETDATE())
    ) as FavoritesLast30Days,
    (
        SELECT TOP 1 p4.Title 
        FROM Posts p4 
        WHERE p4.OwnerUserId = u.Id 
        AND p4.PostTypeId = 1 
        ORDER BY p4.CreationDate DESC
    ) as LatestQuestionTitle,
    (
        SELECT STRING_AGG(t.TagName, ', ') 
        FROM Tags t 
        INNER JOIN (
            SELECT DISTINCT SUBSTRING(p5.Tags, 2, LEN(p5.Tags) - 2) as TagList 
            FROM Posts p5 
            WHERE p5.OwnerUserId = u.Id 
            AND p5.PostTypeId = 1 
            AND p5.Tags IS NOT NULL
        ) taglist ON taglist.TagList LIKE '%' + t.TagName + '%'
        WHERE t.Count > 10
    ) as PopularTags,
    (
        SELECT STRING_AGG(ph2.Text, ' | ') 
        FROM PostHistory ph2 
        WHERE ph2.UserId = u.Id 
        AND ph2.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
        ORDER BY ph2.CreationDate DESC
        OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY
    ) as RecentEditsSample,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND((COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0) / 
                  NULLIF(COUNT(DISTINCT p.Id), 0), 2)
        ELSE 0 
    END as AnswerPercentage,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(
                COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) +
                COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0), 2)
        ELSE 0 
    END as TotalScore,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(AVG(p.Score), 2)
        ELSE 0 
    END as AvgPostScore,
    ROUND(
        (COUNT(DISTINCT p.Id) * 100.0) / 
        NULLIF((SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id), 0), 2
    ) as ActivityPercentage,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        INNER JOIN Posts p6 ON pl.PostId = p6.Id 
        WHERE p6.OwnerUserId = u.Id 
        AND pl.LinkTypeId = 1
    ) as LinkedPosts,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl2 
        INNER JOIN Posts p7 ON pl2.PostId = p7.Id 
        WHERE p7.OwnerUserId = u.Id 
        AND pl2.LinkTypeId = 3
    ) as DuplicatePosts,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl3 
        INNER JOIN Posts p8 ON pl3.RelatedPostId = p8.Id 
        WHERE p8.OwnerUserId = u.Id 
        AND pl3.LinkTypeId = 3
    ) as DuplicateOfOtherUsers,
    (
        SELECT COUNT(*) 
        FROM Posts p9 
        WHERE p9.OwnerUserId = u.Id 
        AND p9.PostTypeId = 1 
        AND p9.AcceptedAnswerId IS NOT NULL
    ) as QuestionsWithAcceptedAnswers,
    (
        SELECT COUNT(DISTINCT ph3.UserId) 
        FROM PostHistory ph3 
        INNER JOIN Posts p10 ON ph3.PostId = p10.Id 
        WHERE p10.OwnerUserId = u.Id 
        AND ph3.UserId IS NOT NULL
    ) as UsersWhoEditedOwnPosts,
    (
        SELECT COUNT(*) 
        FROM Posts p11 
        WHERE p11.OwnerUserId = u.Id 
        AND p11.PostTypeId = 1 
        AND p11.ViewCount > 1000
    ) as HighlyViewedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p12 
        WHERE p12.OwnerUserId = u.Id 
        AND p12.PostTypeId = 2 
        AND p12.Score > 5
    ) as HighScoringAnswers,
    (
        SELECT COUNT(*) 
        FROM Votes v3 
        WHERE v3.UserId = u.Id 
        AND v3.VoteTypeId IN (2, 3)
    ) as UpDownVoteCount,
    (
        SELECT COUNT(*) 
        FROM Votes v4 
        WHERE v4.UserId = u.Id 
        AND v4.VoteTypeId IN (2, 3, 5)
    ) as TotalInteractionVotes,
    (
        SELECT AVG(v5.Score) 
        FROM Votes v5 
        WHERE v5.UserId = u.Id 
        AND v5.VoteTypeId IN (2, 3)
    ) as AvgVoteScore,
    (
        SELECT MAX(v6.CreationDate) 
        FROM Votes v6 
        WHERE v6.UserId = u.Id 
        AND v6.VoteTypeId = 2
    ) as LastUpvoteDate,
    (
        SELECT MAX(v7.CreationDate) 
        FROM Votes v7 
        WHERE v7.UserId = u.Id 
        AND v7.VoteTypeId = 3
    ) as LastDownvoteDate,
    (
        SELECT COUNT(*) 
        FROM Badges b2 
        WHERE b2.UserId = u.Id 
        AND b2.Date >= DATEADD(day, -7, GETDATE())
    ) as BadgesLastWeek,
    (
        SELECT COUNT(DISTINCT b3.Name) 
        FROM Badges b3 
        WHERE b3.UserId = u.Id 
        AND b3.Name LIKE 'Popular%'
    ) as PopularBadgeCount,
    (
        SELECT COUNT(DISTINCT b4.Name) 
        FROM Badges b4 
        WHERE b4.UserId = u.Id 
        AND b4.Class = 1
    ) as GoldBadgeNamesCount,
    (
        SELECT STRING_AGG(b5.Name, ', ') 
        FROM Badges b5 
        WHERE b5.UserId = u.Id 
        AND b5.Date >= DATEADD(day, -30, GETDATE())
        ORDER BY b5.Date DESC
        OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY
    ) as RecentBadges,
    ROUND(
        NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END), 0) * 1.0 / NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0), 2
    ) as AnswerToQuestionRatio,
    (
        SELECT COUNT(DISTINCT ph4.PostId) 
        FROM PostHistory ph4 
        WHERE ph4.UserId = u.Id 
        AND ph4.PostHistoryTypeId IN (2, 5)
        AND ph4.CreationDate >= DATEADD(day, -30, GETDATE())
    ) as ActiveEditingDays,
    (
        SELECT COUNT(*) 
        FROM Posts p13 
        WHERE p13.OwnerUserId = u.Id 
        AND p13.PostTypeId = 1 
        AND p13.CreationDate >= DATEADD(day, -30, GETDATE())
    ) as NewQuestionsLast30Days,
    (
        SELECT COUNT(*) 
        FROM Posts p14 
        WHERE p14.OwnerUserId = u.Id 
        AND p14.PostTypeId = 1 
        AND p14.LastEditDate IS NOT NULL
    ) as EditedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p15 
        WHERE p15.OwnerUserId = u.Id 
        AND p15.PostTypeId = 2 
        AND p15.LastEditDate IS NOT NULL
    ) as EditedAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p16 
        WHERE p16.OwnerUserId = u.Id 
        AND p16.PostTypeId = 1 
        AND p16.Tags IS NOT NULL
        AND p16.Tags != ''
    ) as TaggedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p17 
        WHERE p17.OwnerUserId = u.Id 
        AND p17.PostTypeId IN (2, 1) 
        AND p17.CommentCount > 0
    ) as CommentedPosts,
    (
        SELECT COUNT(*) 
        FROM Posts p18 
        WHERE p18.OwnerUserId = u.Id 
        AND p18.PostTypeId = 1 
        AND p18.AnswerCount > 10
    ) as HighAnswerCountQuestions,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p19.OwnerUserId, COUNT(*) as PostCount
            FROM Posts p19 
            WHERE p19.PostTypeId = 1 
            GROUP BY p19.OwnerUserId
            HAVING COUNT(*) >= 100
        ) highq 
        WHERE highq.OwnerUserId = u.Id
    ) as TopQuestionPoster,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p20.OwnerUserId, COUNT(*) as AnswerCount
            FROM Posts p20 
            WHERE p20.PostTypeId = 2 
            GROUP BY p20.OwnerUserId
            HAVING COUNT(*) >= 100
        ) higha 
        WHERE higha.OwnerUserId = u.Id
    ) as TopAnswerPoster,
    (
        SELECT COUNT(*) 
        FROM Badges b6 
        WHERE b6.UserId = u.Id 
        AND b6.Class = 1 
        AND b6.Name IN ('Fanatic', 'Stellar', 'Epic', 'Legendary')
    ) as EpicGoldBadges,
    (
        SELECT STRING_AGG(ph5.Comment, ', ') 
        FROM PostHistory ph5 
        WHERE ph5.UserId = u.Id 
        AND ph5.Comment IS NOT NULL 
        AND LEN(ph5.Comment) > 5
        ORDER BY ph5.CreationDate DESC
        OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY
    ) as RecentComments,
    (
        SELECT AVG(DATEDIFF(day, p21.CreationDate, p21.LastEditDate)) 
        FROM Posts p21 
        WHERE p21.OwnerUserId = u.Id 
        AND p21.LastEditDate IS NOT NULL
    ) as AvgDaysToEdit,
    (
        SELECT COUNT(*) 
        FROM Posts p22 
        WHERE p22.OwnerUserId = u.Id 
        AND p22.PostTypeId = 1 
        AND (p22.ViewCount >= 1000 OR p22.Score >= 10)
    ) as HighImpactQuestions,
    (
        SELECT COUNT(DISTINCT ph6.UserId) 
        FROM PostHistory ph6 
        WHERE ph6.PostId IN (
            SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1
        )
        AND ph6.UserId IS NOT NULL
    ) as UniqueEditorsOfUserQuestions,
    (
        SELECT STRING_AGG(
            CASE 
                WHEN ph7.PostHistoryTypeId = 1 THEN 'Title Init'
                WHEN ph7.PostHistoryTypeId = 2 THEN 'Body Init'
                WHEN ph7.PostHistoryTypeId = 4 THEN 'Title Edit'
                WHEN ph7.PostHistoryTypeId = 5 THEN 'Body Edit'
                ELSE 'Other'
            END, ', '
        ) 
        FROM PostHistory ph7 
        WHERE ph7.UserId = u.Id 
        AND ph7.PostHistoryTypeId IN (1, 2, 4, 5)
        ORDER BY ph7.CreationDate DESC
        OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY
    ) as RecentEditTypes,
    (
        SELECT MAX(p23.CreationDate) 
        FROM Posts p23 
        WHERE p23.OwnerUserId = u.Id
    ) as LatestPostDate,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT u2.Id, COUNT(*) as PostCount
            FROM Users u2 
            INNER JOIN Posts p24 ON u2.Id = p24.OwnerUserId
            WHERE u2.Id IN (SELECT Id FROM Users WHERE Reputation > 10000)
            GROUP BY u2.Id
            HAVING COUNT(*) >= 50
        ) highrep
        WHERE highrep.Id = u.Id
    ) as HighRepUserWithManyPosts,
    (
        SELECT ROUND(AVG(p25.Score), 2)
        FROM Posts p25 
        WHERE p25.OwnerUserId = u.Id 
        AND p25.PostTypeId = 1 
    ) as AvgQuestionScore,
    (
        SELECT ROUND(AVG(p26.Score), 2)
        FROM Posts p26 
        WHERE p26.OwnerUserId = u.Id 
        AND p26.PostTypeId = 2 
    ) as AvgAnswerScore,
    (
        SELECT COUNT(*) 
        FROM Posts p27 
        WHERE p27.OwnerUserId = u.Id 
        AND p27.PostTypeId = 1 
        AND p27.AcceptedAnswerId IS NOT NULL
        AND p27.Score > 0
    ) as AcceptedQuestionsWithScore,
    (
        SELECT COUNT(*) 
        FROM Comments c2 
        WHERE c2.UserId = u.Id 
        AND c2.CreationDate >= DATEADD(day, -30, GETDATE())
    ) as RecentCommentsCount,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT DISTINCT p28.OwnerUserId
            FROM Posts p28 
            WHERE p28.OwnerUserId IN (
                SELECT OwnerUserId 
                FROM Posts 
                WHERE PostTypeId = 1 
                AND Score > 10
            )
        ) highscore 
        WHERE highscore.OwnerUserId = u.Id
    ) as ActiveWithHighScores,
    (
        SELECT COUNT(*) 
        FROM Posts p29 
        WHERE p29.OwnerUserId = u.Id 
        AND p29.PostTypeId = 1 
        AND p29.CreationDate > DATEADD(day, -7, GETDATE())
    ) as RecentQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p30 
        WHERE p30.OwnerUserId = u.Id 
        AND p30.PostTypeId = 2 
        AND p30.CreationDate > DATEADD(day, -7, GETDATE())
    ) as RecentAnswers,
    (
        SELECT STRING_AGG(CONCAT(
            'Q', p31.Id, ':', 
            LEFT(p31.Title, 30), '...', 
            ' S:', p31.Score,
            ' V:', p31.ViewCount
        ), '; ')
        FROM Posts p31 
        WHERE p31.OwnerUserId = u.Id 
        AND p31.PostTypeId = 1 
        AND p31.CreationDate >= DATEADD(day, -30, GETDATE())
        ORDER BY p31.Score DESC
        OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY
    ) as RecentQuestionScores,
    (
        SELECT STRING_AGG(CONCAT(
            'A', p32.Id, ':', 
            ' S:', p32.Score,
            ' C:', p32.CommentCount
        ), '; ')
        FROM Posts p32 
        WHERE p32.OwnerUserId = u.Id 
        AND p32.PostTypeId = 2 
        AND p32.CreationDate >= DATEADD(day, -30, GETDATE())
        ORDER BY p32.Score DESC
        OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY
    ) as RecentAnswerScores,
    (
        SELECT COUNT(*) 
        FROM Posts p33 
        WHERE p33.OwnerUserId = u.Id 
        AND p33.PostTypeId = 1 
        AND p33.ViewCount > 5000
    ) as ViralQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p34 
        WHERE p34.OwnerUserId = u.Id 
        AND p34.PostTypeId = 2 
        AND p34.Score > 100
    ) as HighScoreAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p35 
        WHERE p35.OwnerUserId = u.Id 
        AND p35.PostTypeId = 1 
        AND p35.AnswerCount >= 10
    ) as QuestionsWithManyAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p36 
        WHERE p36.OwnerUserId = u.Id 
        AND p36.PostTypeId = 1 
        AND p36.LastActivityDate >= DATEADD(day, -7, GETDATE())
    ) as RecentlyActiveQuestions,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p37.OwnerUserId, COUNT(*) as ScoreCount
            FROM Posts p37 
            WHERE p37.OwnerUserId = u.Id 
            AND p37.PostTypeId = 1 
            AND p37.Score > 0
            GROUP BY p37.OwnerUserId
            HAVING COUNT(*) >= 5
        ) highscorecount 
        WHERE highscorecount.OwnerUserId = u.Id
    ) as FrequentScorers,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p38.OwnerUserId, COUNT(*) as CommentCount
            FROM Comments p38 
            WHERE p38.UserId = u.Id 
            GROUP BY p38.OwnerUserId
            HAVING COUNT(*) >= 3
        ) highcomment 
        WHERE highcomment.OwnerUserId = u.Id
    ) as FrequentCommenters,
    (
        SELECT COUNT(*) 
        FROM Posts p39 
        WHERE p39.OwnerUserId = u.Id 
        AND p39.PostTypeId = 1 
        AND p39.Tags IS NOT NULL
    ) as TotalTaggedQuestions,
    (
        SELECT STRING_AGG(p40.Title, ', ') 
        FROM Posts p40 
        WHERE p40.OwnerUserId = u.Id 
        AND p40.PostTypeId = 1 
        AND p40.Tags LIKE '%python%'
        ORDER BY p40.CreationDate DESC
        OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY
    ) as RecentPythonQuestions,
    (
        SELECT STRING_AGG(p41.Title, ', ') 
        FROM Posts p41 
        WHERE p41.OwnerUserId = u.Id 
        AND p41.PostTypeId = 1 
        AND p41.Tags LIKE '%javascript%'
        ORDER BY p41.CreationDate DESC
        OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY
    ) as RecentJavaScriptQuestions,
    (
        SELECT COUNT(DISTINCT p42.ParentId) 
        FROM Posts p42 
        WHERE p42.OwnerUserId = u.Id 
        AND p42.PostTypeId = 2 
        AND p42.ParentId IS NOT NULL
    ) as TotalAnsweredQuestions,
    (
        SELECT COUNT(DISTINCT p43.ParentId) 
        FROM Posts p43 
        WHERE p43.OwnerUserId = u.Id 
        AND p43.PostTypeId = 2 
        AND p43.ParentId IS NOT NULL
        AND p43.CreationDate >= DATEADD(day, -30, GETDATE())
    ) as RecentAnsweredQuestions,
    (
        SELECT ROUND(AVG(p44.Score * 1.0), 2) 
        FROM Posts p44 
        WHERE p44.OwnerUserId = u.Id 
        AND p44.PostTypeId = 2 
        AND p44.Score > 0
    ) as AvgNonZeroAnswerScore,
    (
        SELECT ROUND(AVG(p45.Score * 1.0), 2)
        FROM Posts p45 
        WHERE p45.OwnerUserId = u.Id 
        AND p45.PostTypeId = 1 
        AND p45.Score > 0
    ) as AvgNonZeroQuestionScore,
    (
        SELECT MIN(p46.Score) 
        FROM Posts p46 
        WHERE p46.OwnerUserId = u.Id 
        AND p46.PostTypeId = 1 
    ) as MinQuestionScore,
    (
        SELECT MAX(p47.Score) 
        FROM Posts p47 
        WHERE p47.OwnerUserId = u.Id 
        AND p47.PostTypeId = 2 
    ) as MaxAnswerScore,
    (
        SELECT COUNT(*) 
        FROM Posts p48 
        WHERE p48.OwnerUserId = u.Id 
        AND p48.PostTypeId = 1 
        AND p48.FavoriteCount > 0
    ) as QuestionsWithFavorites,
    (
        SELECT COUNT(*) 
        FROM Posts p49 
        WHERE p49.OwnerUserId = u.Id 
        AND p49.PostTypeId = 2 
        AND p49.FavoriteCount > 0
    ) as AnswersWithFavorites,
    (
        SELECT COUNT(DISTINCT p50.OwnerUserId) 
        FROM Posts p50 
        WHERE p50.PostTypeId = 1 
        AND p50.OwnerUserId IS NOT NULL
        AND p50.OwnerUserId <> u.Id
    ) as OtherActiveUsers,
    (
        SELECT COUNT(*) 
        FROM Votes v8 
        WHERE v8.UserId = u.Id 
        AND v8.VoteTypeId IN (2, 3, 5, 14, 16)
    ) as TotalVoteTypes,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph8 
        WHERE ph8.UserId = u.Id 
        AND ph8.PostHistoryTypeId = 25
    ) as PostsTweeted,
    (
        SELECT COUNT(*) 
        FROM Badges b7 
        WHERE b7.UserId = u.Id 
        AND b7.Name IN ('Great Answer', 'Great Question')
    ) as GreatQuestionAnswer,
    (
        SELECT COUNT(*) 
        FROM Posts p51 
        WHERE p51.OwnerUserId = u.Id 
        AND p51.PostTypeId = 1 
        AND p51.LastEditDate > p51.CreationDate
    ) as EditedQuestionsCount,
    (
        SELECT COUNT(*) 
        FROM Posts p52 
        WHERE p52.OwnerUserId = u.Id 
        AND p52.PostTypeId = 2 
        AND p52.LastEditDate > p52.CreationDate
    ) as EditedAnswersCount,
    (
        SELECT STRING_AGG(b8.Name, ', ') 
        FROM Badges b8 
        WHERE b8.UserId = u.Id 
        AND b8.Class = 2 
        AND b8.Name LIKE '%Nobel%'
        ORDER BY b8.Date DESC
        OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY
    ) as NobelSilverBadge,
    (
        SELECT STRING_AGG(b9.Name, ', ') 
        FROM Badges b9 
        WHERE b9.UserId = u.Id 
        AND b9.Class = 3 
        AND b9.Name LIKE '%Scholar%'
        ORDER BY b9.Date DESC
        OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY
    ) as ScholarBronzeBadge,
    (
        SELECT COUNT(*) 
        FROM Posts p53 
        WHERE p53.OwnerUserId = u.Id 
        AND p53.PostTypeId = 1 
        AND p53.CreationDate >= DATEADD(day, -90, GETDATE())
    ) as QuestionsLast90Days,
    (
        SELECT COUNT(*) 
        FROM Posts p54 
        WHERE p54.OwnerUserId = u.Id 
        AND p54.PostTypeId = 2 
        AND p54.CreationDate >= DATEADD(day, -90, GETDATE())
    ) as AnswersLast90Days,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT ph9.PostId, COUNT(*) as EditCount
            FROM PostHistory ph9 
            WHERE ph9.UserId = u.Id 
            AND ph9.PostHistoryTypeId IN (2, 5)
            GROUP BY ph9.PostId
            HAVING COUNT(*) >= 3
        ) frequentedit
    ) as FrequentlyEditedPosts,
    (
        SELECT COUNT(*) 
        FROM Posts p55 
        WHERE p55.OwnerUserId = u.Id 
        AND p55.PostTypeId = 2 
        AND p55.Score < 0
    ) as NegativeScoreAnswers,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p56.OwnerUserId
            FROM Posts p56 
            WHERE p56.OwnerUserId = u.Id 
            AND p56.PostTypeId = 1
            GROUP BY p56.OwnerUserId
            HAVING COUNT(*) >= 100
        ) highquestions 
        WHERE highquestions.OwnerUserId = u.Id
    ) as HighQuestionUser,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p57.OwnerUserId
            FROM Posts p57 
            WHERE p57.OwnerUserId = u.Id 
            AND p57.PostTypeId = 2
            GROUP BY p57.OwnerUserId
            HAVING COUNT(*) >= 100
        ) highanswers 
        WHERE highanswers.OwnerUserId = u.Id
    ) as HighAnswerUser,
    (
        SELECT STRING_AGG(v9.VoteTypeId, ', ') 
        FROM Votes v9 
        WHERE v9.UserId = u.Id 
        AND v9.VoteTypeId IN (2, 3, 5)
        ORDER BY v9.CreationDate DESC
        OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY
    ) as RecentVoteTypes,
    (
        SELECT STRING_AGG(
            CASE 
                WHEN v10.VoteTypeId = 2 THEN 'Upvote'
                WHEN v10.VoteTypeId = 3 THEN 'Downvote'
                WHEN v10.VoteTypeId = 5 THEN 'Favorite'
                ELSE 'Other'
            END, ', ')
        FROM Votes v10 
        WHERE v10.UserId = u.Id 
        AND v10.VoteTypeId IN (2, 3, 5)
        ORDER BY v10.CreationDate DESC
        OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY
    ) as RecentVoteTypeNames,
    (
        SELECT COUNT(*) 
        FROM Posts p58 
        WHERE p58.OwnerUserId = u.Id 
        AND p58.PostTypeId = 1 
        AND (p58.ViewCount IS NULL OR p58.ViewCount <= 0)
    ) as UnviewedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p59 
        WHERE p59.OwnerUserId = u.Id 
        AND p59.PostTypeId = 2 
        AND (p59.ViewCount IS NULL OR p59.ViewCount <= 0)
    ) as UnviewedAnswers,
    (
        SELECT COALESCE(SUM(CASE WHEN v11.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) +
               COALESCE(SUM(CASE WHEN v11.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) as TotalUpVotesFavorites
        FROM Votes v11 
        WHERE v11.UserId = u.Id 
        AND v11.VoteTypeId IN (2, 5)
    ) as UpVotesFavorites,
    (
        SELECT COUNT(*) 
        FROM Badges b10 
        WHERE b10.UserId = u.Id 
        AND b10.Date >= DATEADD(day, -60, GETDATE())
    ) as BadgesLast60Days,
    (
        SELECT STRING_AGG(
            CASE 
                WHEN ph10.PostHistoryTypeId = 1 THEN 'Initial Title'
                WHEN ph10.PostHistoryTypeId = 2 THEN 'Initial Body'
                WHEN ph10.PostHistoryTypeId = 4 THEN 'Title Edit'
                WHEN ph10.PostHistoryTypeId = 5 THEN 'Body Edit'
                WHEN ph10.PostHistoryTypeId = 6 THEN 'Tag Edit'
                ELSE 'Other'
            END, ', ')
        FROM PostHistory ph10 
        WHERE ph10.UserId = u.Id 
        AND ph10.PostHistoryTypeId IN (1, 2, 4, 5, 6)
        ORDER BY ph10.CreationDate DESC
        OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY
    ) as RecentPostHistoryTypes,
    (
        SELECT COUNT(DISTINCT c3.Id) 
        FROM Comments c3 
        WHERE c3.UserId = u.Id 
        AND c3.PostId IN (
            SELECT Id FROM Posts WHERE OwnerUserId = u.Id
        )
    ) as CommentsOnOwnPosts,
    (
        SELECT COUNT(DISTINCT p60.Id) 
        FROM Posts p60 
        WHERE p60.OwnerUserId = u.Id 
        AND p60.PostTypeId = 1 
        AND p60.ClosedDate IS NOT NULL
    ) as ClosedQuestions,
    (
        SELECT COUNT(DISTINCT p61.Id) 
        FROM Posts p61 
        WHERE p61.OwnerUserId = u.Id 
        AND p61.PostTypeId = 1 
        AND p61.LastActivityDate >= DATEADD(day, -14, GETDATE())
    ) as ActiveLast14Days,
    (
        SELECT STRING_AGG(p62.Title, ' | ') 
        FROM Posts p62 
        WHERE p62.OwnerUserId = u.Id 
        AND p62.PostTypeId = 1 
        AND p62.CreationDate >= DATEADD(day, -7, GETDATE())
        ORDER BY p62.CreationDate DESC
        OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY
    ) as RecentQuestionTitles,
    -- Window function example - ranking by reputation within top 50 users
    RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
    -- Set operator and complex predicates
    CASE 
        WHEN u.Reputation > 1000000 THEN 'Megarep'
        WHEN u.Reputation > 100000 THEN 'GreatRep'
        WHEN u.Reputation > 10000 THEN 'GoodRep'
        WHEN u.Reputation > 1000 THEN 'FairRep'
        ELSE 'LowRep'
    END as ReputationTier,
    -- NULL handling with COALESCE and ISNULL
    ISNULL(u.WebsiteUrl, 'No Website') as WebsiteUrl,
    ISNULL(u.Location, 'Unknown Location') as Location,
    ISNULL(CONVERT(VARCHAR(10), u.CreationDate, 101), 'Unknown') as AccountCreationDate,
    COALESCE(u.DisplayName, 'Anonymous User') as DisplayOrAnonymous,
    CASE 
        WHEN u.LastAccessDate > DATEADD(day, -7, GETDATE()) THEN 'Active'
        WHEN u.LastAccessDate > DATEADD(day, -30, GETDATE()) THEN 'Moderately Active'
        ELSE 'Inactive'
    END as ActivityStatus,
    -- Complex mathematical and string expressions
    ROUND(
        (COALESCE(SUM(p.Score), 0) * 1.0 / NULLIF(COUNT(DISTINCT p.Id), 0)), 2
    ) as AvgScorePerPost,
    ROUND(
        (COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) * 100.0 / NULLIF(COUNT(DISTINCT b.Id), 0)), 2
    ) as GoldBadgePercentage,
    ROUND(
        (COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) * 100.0 / NULLIF(COUNT(DISTINCT b.Id), 0)), 2
    ) as SilverBadgePercentage,
    ROUND(
        (COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) * 100.0 / NULLIF(COUNT(DISTINCT b.Id), 0)), 2
    ) as BronzeBadgePercentage,
    (
        SELECT COUNT(*) 
        FROM (VALUES (u.UpVotes), (u.DownVotes), (u.Views)) v(value)
        WHERE v.value > 5000
    ) as HighStatsCount
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
WHERE u.Id BETWEEN 1 AND 10000
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    u.LastAccessDate,
    u.WebsiteUrl,
    u.Location,
    u.CreationDate,
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 0
    AND COUNT(DISTINCT b.Id) > 0
    AND (MIN(p.CreationDate) >= DATEADD(year, -1, GETDATE()) OR COUNT(DISTINCT p.Id) > 10)
ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;