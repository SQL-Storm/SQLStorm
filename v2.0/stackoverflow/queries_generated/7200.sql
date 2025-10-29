-- {"query": "7200.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 8173} 
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
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) as Wikis,
    COUNT(DISTINCT CASE WHEN p.PostTypeId IN (4,5) THEN p.Id END) as TagWikis,
    COUNT(DISTINCT b.Id) as Badges,
    COUNT(DISTINCT c.Id) as Comments,
    COUNT(DISTINCT ph.Id) as PostHistoryEntries,
    COUNT(DISTINCT pl.Id) as PostLinks,
    COUNT(DISTINCT v.Id) as Votes,
    COALESCE(SUM(p.Score), 0) as TotalScore,
    COALESCE(AVG(p.Score), 0) as AverageScore,
    COALESCE(MAX(p.Score), 0) as MaxScore,
    COALESCE(MIN(p.Score), 0) as MinScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) as TotalQuestionViews,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END), 0) as TotalAnswerViews,
    COALESCE(SUM(p.ViewCount), 0) as TotalViews,
    STRING_AGG(DISTINCT t.TagName, ', ') as UserTags,
    STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Tags END, ', ') as QuestionTags,
    STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, ' | ') as QuestionTitles,
    STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Body END, ' | ') as AnswerBodies,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) as QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) as QuestionsWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount > 0 THEN p.Id END) as QuestionsWithFavorites,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Id END) as HighScoringAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score < 0 THEN p.Id END) as LowScoringAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id END) as CommunityOwnedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CreationDate > '2022-01-01' THEN p.Id END) as RecentQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CreationDate > '2022-01-01' THEN p.Id END) as RecentAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CreationDate BETWEEN '2022-01-01' AND '2022-12-31' THEN p.Id END) as Questions2022,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CreationDate BETWEEN '2022-01-01' AND '2022-12-31' THEN p.Id END) as Answers2022,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score > 100 THEN p.Id END) as HighlyScoredQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 100 THEN p.Id END) as HighlyScoredAnswers,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 2 THEN pv.Id END) as Upvotes,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 3 THEN pv.Id END) as Downvotes,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 5 THEN pv.Id END) as Favorites,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 1 THEN pv.Id END) as AcceptedAnswers,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 6 THEN pv.Id END) as CloseVotes,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 7 THEN pv.Id END) as ReopenVotes,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 8 THEN pv.Id END) as BountyStarts,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 9 THEN pv.Id END) as BountyCloses,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 10 THEN pv.Id END) as Deletions,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 11 THEN pv.Id END) as Undeletions,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 12 THEN pv.Id END) as Spams,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 14 THEN pv.Id END) as ModeratorNominations,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 15 THEN pv.Id END) as ModeratorReviews,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 16 THEN pv.Id END) as ApproveEditSuggestions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1,4,7) THEN ph.Id END) as TitleEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2,5,8) THEN ph.Id END) as BodyEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (3,6,9) THEN ph.Id END) as TagEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) as PostClosed,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) as PostReopened,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.Id END) as PostDeleted,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.Id END) as PostUndeleted,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 14 THEN ph.Id END) as PostLocked,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 15 THEN ph.Id END) as PostUnlocked,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.Id END) as CommunityOwned,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (17,35,36) THEN ph.Id END) as PostMigrations,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (18,19,20) THEN ph.Id END) as QuestionModifications,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (22,37,38) THEN ph.Id END) as QuestionMergeRelated,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 24 THEN ph.Id END) as SuggestedEditApplied,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 25 THEN ph.Id END) as PostTweeted,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (31,33,34) THEN ph.Id END) as DiscussionRelated,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (50,52,53) THEN ph.Id END) as HotRelated,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 66 THEN ph.Id END) as CreatedFromWizard,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
    RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as ScoreRank,
    PERCENT_RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0)) as ScorePercentile,
    NTILE(10) OVER (ORDER BY COALESCE(SUM(p.Score), 0)) as ScoreDecile,
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as ScoreRowNumber,
    LAG(COUNT(DISTINCT p.Id), 1, 0) OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as PreviousUserPosts,
    LEAD(COUNT(DISTINCT p.Id), 1, 0) OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as NextUserPosts,
    FIRST_VALUE(COUNT(DISTINCT p.Id)) OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as MaxPosts,
    LAST_VALUE(COUNT(DISTINCT p.Id)) OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as MinPosts,
    AVG(COUNT(DISTINCT p.Id)) OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) as MovingAvgPosts,
    STDDEV_SAMP(COUNT(DISTINCT p.Id)) OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) as MovingStdDevPosts,
    CONCAT(
        'User-', 
        u.Id, 
        '-Reputation-', 
        u.Reputation, 
        '-Posts-', 
        COUNT(DISTINCT p.Id),
        '-Score-', 
        COALESCE(SUM(p.Score), 0),
        '-Badges-', 
        COUNT(DISTINCT b.Id),
        '-Comments-', 
        COUNT(DISTINCT c.Id)
    ) as UserSummary,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 1000 THEN 'Super User'
        WHEN COUNT(DISTINCT p.Id) > 500 THEN 'Expert User' 
        WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Regular User'
        WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Beginner User'
        ELSE 'New User'
    END as UserLevel,
    CASE 
        WHEN COALESCE(SUM(p.Score), 0) > 10000 THEN 'Legendary'
        WHEN COALESCE(SUM(p.Score), 0) > 5000 THEN 'Master' 
        WHEN COALESCE(SUM(p.Score), 0) > 1000 THEN 'Expert' 
        WHEN COALESCE(SUM(p.Score), 0) > 100 THEN 'Novice'
        ELSE 'Beginner'
    END as ReputationLevel,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 THEN 
            CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS FLOAT) / 
            COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)
        ELSE 0
    END as AnswerToQuestionRatio,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 THEN 
            CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) AS FLOAT) / 
            COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)
        ELSE 0
    END as CommentedQuestionRatio,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 THEN 
            CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount > 0 THEN p.Id END) AS FLOAT) / 
            COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)
        ELSE 0
    END as FavoritedQuestionRatio,
    IIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) > 0, 
        CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score > 0 THEN p.Id END) AS FLOAT) / 
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END),
        0) as HighScoreClosedQuestionRatio,
    IIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id END) > 0, 
        CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) AS FLOAT) / 
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id END),
        0) as AnsweredCommunityOwnedQuestionRatio,
    CASE WHEN EXISTS (
        SELECT 1 FROM PostHistory ph2 
        WHERE ph2.UserId = u.Id AND ph2.PostHistoryTypeId = 10 
        AND ph2.CreationDate > '2022-01-01'
    ) THEN 1 ELSE 0 END as HasRecentCloseVotes,
    CASE WHEN EXISTS (
        SELECT 1 FROM Votes v2 
        WHERE v2.UserId = u.Id AND v2.VoteTypeId = 6 
        AND v2.CreationDate > '2022-01-01'
    ) THEN 1 ELSE 0 END as HasRecentCloseVotes2,
    CASE WHEN EXISTS (
        SELECT 1 FROM Badges b2 
        WHERE b2.UserId = u.Id AND b2.Date > '2022-01-01'
    ) THEN 1 ELSE 0 END as HasRecentBadges,
    CASE WHEN EXISTS (
        SELECT 1 FROM Comments c2 
        WHERE c2.UserId = u.Id AND c2.CreationDate > '2022-01-01'
    ) THEN 1 ELSE 0 END as HasRecentComments,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id AND p2.CreationDate > '2022-01-01'
        AND p2.PostTypeId = 1
    ) THEN 1 ELSE 0 END as HasRecentQuestions,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id AND p3.CreationDate > '2022-01-01'
        AND p3.PostTypeId = 2
    ) THEN 1 ELSE 0 END as HasRecentAnswers,
    COALESCE(
        (SELECT COUNT(DISTINCT bp.Id) 
         FROM Badges bp 
         WHERE bp.UserId = u.Id 
         AND bp.Class = 1), 0) as GoldBadges,
    COALESCE(
        (SELECT COUNT(DISTINCT bp.Id) 
         FROM Badges bp 
         WHERE bp.UserId = u.Id 
         AND bp.Class = 2), 0) as SilverBadges,
    COALESCE(
        (SELECT COUNT(DISTINCT bp.Id) 
         FROM Badges bp 
         WHERE bp.UserId = u.Id 
         AND bp.Class = 3), 0) as BronzeBadges,
    COALESCE(
        (SELECT AVG(p4.Score) 
         FROM Posts p4 
         WHERE p4.OwnerUserId = u.Id), 0) as AvgUserScore,
    COALESCE(
        (SELECT MAX(p5.Score) 
         FROM Posts p5 
         WHERE p5.OwnerUserId = u.Id), 0) as MaxUserScore,
    COALESCE(
        (SELECT MIN(p6.Score) 
         FROM Posts p6 
         WHERE p6.OwnerUserId = u.Id), 0) as MinUserScore,
    COALESCE(
        (SELECT AVG(p7.ViewCount) 
         FROM Posts p7 
         WHERE p7.OwnerUserId = u.Id), 0) as AvgUserViews,
    COALESCE(
        (SELECT COUNT(DISTINCT pl2.Id) 
         FROM PostLinks pl2 
         WHERE pl2.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
         AND pl2.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)), 0) as UserToUserLinks,
    COALESCE(
        (SELECT COUNT(DISTINCT pl3.Id) 
         FROM PostLinks pl3 
         WHERE pl3.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
         AND pl3.RelatedPostId NOT IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)), 0) as UserToExternalLinks,
    COALESCE(
        (SELECT COUNT(DISTINCT pl4.Id) 
         FROM PostLinks pl4 
         WHERE pl4.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
         AND pl4.PostId NOT IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)), 0) as ExternalToUserLinks,
    COALESCE(
        (SELECT COUNT(DISTINCT pl5.Id) 
         FROM PostLinks pl5 
         WHERE pl5.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
         AND pl5.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
         AND pl5.LinkTypeId = 3), 0) as DuplicateUserLinks,
    COALESCE(
        (SELECT COUNT(DISTINCT pl6.Id) 
         FROM PostLinks pl6 
         WHERE pl6.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
         AND pl6.RelatedPostId NOT IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
         AND pl6.LinkTypeId = 1), 0) as LinkedExternalPosts,
    COALESCE(
        (SELECT COUNT(DISTINCT ph2.Id) 
         FROM PostHistory ph2 
         WHERE ph2.UserId = u.Id 
         AND ph2.PostHistoryTypeId IN (10, 11, 12, 13)), 0) as ActionHistory,
    COALESCE(
        (SELECT COUNT(DISTINCT ph3.Id) 
         FROM PostHistory ph3 
         WHERE ph3.UserId = u.Id 
         AND ph3.PostHistoryTypeId = 10), 0) as CloseHistory,
    COALESCE(
        (SELECT COUNT(DISTINCT ph4.Id) 
         FROM PostHistory ph4 
         WHERE ph4.UserId = u.Id 
         AND ph4.PostHistoryTypeId = 11), 0) as ReopenHistory,
    COALESCE(
        (SELECT COUNT(DISTINCT ph5.Id) 
         FROM PostHistory ph5 
         WHERE ph5.UserId = u.Id 
         AND ph5.PostHistoryTypeId = 12), 0) as DeleteHistory,
    COALESCE(
        (SELECT COUNT(DISTINCT ph6.Id) 
         FROM PostHistory ph6 
         WHERE ph6.UserId = u.Id 
         AND ph6.PostHistoryTypeId IN (24, 25, 31, 33, 34, 50, 52, 53, 66)), 0) as OtherHistory,
    COALESCE(
        (SELECT COUNT(DISTINCT v2.Id) 
         FROM Votes v2 
         WHERE v2.UserId = u.Id), 0) as TotalVotes,
    COALESCE(
        (SELECT COUNT(DISTINCT v3.Id) 
         FROM Votes v3 
         WHERE v3.UserId = u.Id 
         AND v3.VoteTypeId BETWEEN 1 AND 5), 0) as VoteHistory,
    COALESCE(
        (SELECT COUNT(DISTINCT v4.Id) 
         FROM Votes v4 
         WHERE v4.UserId = u.Id 
         AND v4.VoteTypeId IN (8, 9)), 0) as BountyHistory,
    COALESCE(
        (SELECT COUNT(DISTINCT v5.Id) 
         FROM Votes v5 
         WHERE v5.UserId = u.Id 
         AND v5.VoteTypeId BETWEEN 10 AND 16), 0) as ModerationHistory,
    COALESCE(
        (SELECT COUNT(DISTINCT c2.Id) 
         FROM Comments c2 
         WHERE c2.UserId = u.Id 
         AND c2.CreationDate > '2022-01-01'), 0) as RecentComments,
    COALESCE(
        (SELECT COUNT(DISTINCT c3.Id) 
         FROM Comments c3 
         WHERE c3.UserId = u.Id), 0) as TotalComments,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p8 
        WHERE p8.OwnerUserId = u.Id 
        AND p8.PostTypeId = 1 
        AND p8.AnswerCount > 10
    ) THEN 1 ELSE 0 END as HasHighAnswerQuestion,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p9 
        WHERE p9.OwnerUserId = u.Id 
        AND p9.PostTypeId = 2 
        AND p9.Score > 100
    ) THEN 1 ELSE 0 END as HasHighScoreAnswer,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p10 
        WHERE p10.OwnerUserId = u.Id 
        AND p10.PostTypeId = 1 
        AND p10.ViewCount > 1000
    ) THEN 1 ELSE 0 END as HasPopularQuestion,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p11 
        WHERE p11.OwnerUserId = u.Id 
        AND p11.PostTypeId = 1 
        AND p11.Score < -100
    ) THEN 1 ELSE 0 END as HasHighlyDownvotedQuestion,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p12 
        WHERE p12.OwnerUserId = u.Id 
        AND p12.PostTypeId = 2 
        AND p12.Score < -50
    ) THEN 1 ELSE 0 END as HasHighlyDownvotedAnswer,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p13 
        WHERE p13.OwnerUserId = u.Id 
        AND p13.PostTypeId = 1 
        AND p13.CommentCount > 50
    ) THEN 1 ELSE 0 END as HasHighlyCommentedQuestion,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p14 
        WHERE p14.OwnerUserId = u.Id 
        AND p14.PostTypeId = 1 
        AND p14.FavoriteCount > 100
    ) THEN 1 ELSE 0 END as HasHighlyFavoritedQuestion,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p15 
        WHERE p15.OwnerUserId = u.Id 
        AND p15.PostTypeId = 1 
        AND p15.ClosedDate IS NOT NULL
    ) THEN 1 ELSE 0 END as HasClosedQuestion,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p16 
        WHERE p16.OwnerUserId = u.Id 
        AND p16.PostTypeId = 1 
        AND p16.CommunityOwnedDate IS NOT NULL
    ) THEN 1 ELSE 0 END as HasCommunityOwnedQuestion,
    CASE WHEN EXISTS (
        SELECT 1 FROM Posts p17 
        WHERE p17.OwnerUserId = u.Id 
        AND p17.PostTypeId = 1 
        AND p17.PostTypeId = 2
    ) THEN 1 ELSE 0 END as HasBothQuestionAnswer,
    COALESCE(
        (SELECT COUNT(DISTINCT p18.Id) 
         FROM Posts p18 
         WHERE p18.OwnerUserId = u.Id 
         AND p18.PostTypeId = 1
         AND p18.ViewCount > (
             SELECT AVG(p19.ViewCount) 
             FROM Posts p19 
             WHERE p19.PostTypeId = 1
         )), 0) as AboveAvgViewQuestion,
    COALESCE(
        (SELECT COUNT(DISTINCT p20.Id) 
         FROM Posts p20 
         WHERE p20.OwnerUserId = u.Id 
         AND p20.PostTypeId = 2
         AND p20.ViewCount > (
             SELECT AVG(p21.ViewCount) 
             FROM Posts p21 
             WHERE p21.PostTypeId = 2
         )), 0) as AboveAvgViewAnswer,
    COALESCE(
        (SELECT COUNT(DISTINCT p22.Id) 
         FROM Posts p22 
         WHERE p22.OwnerUserId = u.Id 
         AND p22.PostTypeId = 1
         AND p22.Score > (
             SELECT AVG(p23.Score) 
             FROM Posts p23 
             WHERE p23.PostTypeId = 1
         )), 0) as AboveAvgScoreQuestion,
    COALESCE(
        (SELECT COUNT(DISTINCT p24.Id) 
         FROM Posts p24 
         WHERE p24.OwnerUserId = u.Id 
         AND p24.PostTypeId = 2
         AND p24.Score > (
             SELECT AVG(p25.Score) 
             FROM Posts p25 
             WHERE p25.PostTypeId = 2
         )), 0) as AboveAvgScoreAnswer,
    COALESCE(
        (SELECT COUNT(DISTINCT p26.Id) 
         FROM Posts p26 
         WHERE p26.OwnerUserId = u.Id 
         AND p26.CommentCount > (
             SELECT AVG(p27.CommentCount) 
             FROM Posts p27 
             WHERE p27.OwnerUserId = u.Id
         )), 0) as MoreCommentThanAvg,
    COALESCE(
        (SELECT COUNT(DISTINCT p28.Id) 
         FROM Posts p28 
         WHERE p28.OwnerUserId = u.Id 
         AND p28.FavoriteCount > (
             SELECT AVG(p29.FavoriteCount) 
             FROM Posts p29 
             WHERE p29.OwnerUserId = u.Id
         )), 0) as MoreFavoriteThanAvg,
    COALESCE(
        (SELECT COUNT(DISTINCT p30.Id) 
         FROM Posts p30 
         WHERE p30.OwnerUserId = u.Id 
         AND p30.AnswerCount > (
             SELECT AVG(p31.AnswerCount) 
             FROM Posts p31 
             WHERE p31.OwnerUserId = u.Id
         )), 0) as MoreAnswerThanAvg,
    COALESCE(
        (SELECT COUNT(DISTINCT p32.Id) 
         FROM Posts p32 
         WHERE p32.OwnerUserId = u.Id 
         AND p32.Score > 0
         AND p32.PostTypeId = 1
         AND p32.ViewCount = (
             SELECT MAX(p33.ViewCount) 
             FROM Posts p33 
             WHERE p33.OwnerUserId = u.Id 
             AND p33.PostTypeId = 1
         )), 0) as HighestViewedQuestion,
    COALESCE(
        (SELECT COUNT(DISTINCT p34.Id) 
         FROM Posts p34 
         WHERE p34.OwnerUserId = u.Id 
         AND p34.Score > 0
         AND p34.PostTypeId = 2
         AND p34.ViewCount = (
             SELECT MAX(p35.ViewCount) 
             FROM Posts p35 
             WHERE p35.OwnerUserId = u.Id 
             AND p35.PostTypeId = 2
         )), 0) as HighestViewedAnswer,
    COALESCE(
        (SELECT COUNT(DISTINCT p36.Id) 
         FROM Posts p36 
         WHERE p36.OwnerUserId = u.Id 
         AND p36.Score > 0
         AND p36.PostTypeId = 1
         AND p36.ViewCount > 1000
         AND p36.ViewCount = (
             SELECT MAX(p37.ViewCount) 
             FROM Posts p37 
             WHERE p37.OwnerUserId = u.Id 
             AND p37.PostTypeId = 1
         )), 0) as PopularHighViewedQuestion,
    COALESCE(
        (SELECT COUNT(DISTINCT p38.Id) 
         FROM Posts p38 
         WHERE p38.OwnerUserId = u.Id 
         AND p38.Score > 0
         AND p38.PostTypeId = 2
         AND p38.ViewCount > 1000
         AND p38.ViewCount = (
             SELECT MAX(p39.ViewCount) 
             FROM Posts p39 
             WHERE p39.OwnerUserId = u.Id 
             AND p39.PostTypeId = 2
         )), 0) as PopularHighViewedAnswer,
    COALESCE(
        (SELECT COUNT(DISTINCT p40.Id) 
         FROM Posts p40 
         WHERE p40.OwnerUserId = u.Id 
         AND p40.Score > 0
         AND p40.PostTypeId = 1
         AND p40.AnswerCount > 0
         AND p40.Score = (
             SELECT MAX(p41.Score) 
             FROM Posts p41 
             WHERE p41.OwnerUserId = u.Id 
             AND p41.PostTypeId = 1
         )), 0) as HighestScoredQuestion,
    COALESCE(
        (SELECT COUNT(DISTINCT p42.Id) 
         FROM Posts p42 
         WHERE p42.OwnerUserId = u.Id 
         AND p42.Score > 0
         AND p42.PostTypeId = 2
         AND p42.AnswerCount > 0
         AND p42.Score = (
             SELECT MAX(p43.Score) 
             FROM Posts p43 
             WHERE p43.OwnerUserId = u.Id 
             AND p43.PostTypeId = 2
         )), 0) as HighestScoredAnswer,
    COALESCE(
        (SELECT COUNT(DISTINCT p44.Id) 
         FROM Posts p44 
         WHERE p44.OwnerUserId = u.Id 
         AND p44.Score > 0
         AND p44.PostTypeId = 1
         AND p44.AnswerCount > 0
         AND p44.Score > (
             SELECT AVG(p45.Score) 
             FROM Posts p45 
             WHERE p45.OwnerUserId = u.Id 
             AND p45.PostTypeId = 1
         )
         AND p44.AnswerCount > (
             SELECT AVG(p46.AnswerCount) 
             FROM Posts p46 
             WHERE p46.OwnerUserId = u.Id 
             AND p46.PostTypeId = 1
         )), 0) as AboveAvgScoreAndAnswerQuestion,
    COALESCE(
        (SELECT COUNT(DISTINCT p47.Id) 
         FROM Posts p47 
         WHERE p47.OwnerUserId = u.Id 
         AND p47.Score > 0
         AND p47.PostTypeId = 2
         AND p47.AnswerCount > 0
         AND p47.Score > (
             SELECT AVG(p48.Score) 
             FROM Posts p48 
             WHERE p48.OwnerUserId = u.Id 
             AND p48.PostTypeId = 2
         )
         AND p47.AnswerCount > (
             SELECT AVG(p49.AnswerCount) 
             FROM Posts p49 
             WHERE p49.OwnerUserId = u.Id 
             AND p49.PostTypeId = 2
         )), 0) as AboveAvgScoreAndAnswerAnswer,
    COALESCE(
        (SELECT COUNT(DISTINCT p50.Id) 
         FROM Posts p50 
         WHERE p50.OwnerUserId = u.Id 
         AND p50.PostTypeId = 1
         AND p50.Score > 0
         AND p50.AnswerCount > 0
         AND p50.ViewCount > 1000
         AND p50.CommentCount > 10
         AND p50.FavoriteCount > 10), 0) as HighlyEngagedQuestion,
    COALESCE(
        (SELECT COUNT(DISTINCT p51.Id) 
         FROM Posts p51 
         WHERE p51.OwnerUserId = u.Id 
         AND p51.PostTypeId = 2
         AND p51.Score > 0
         AND p51.AnswerCount > 0
         AND p51.ViewCount > 1000
         AND p51.CommentCount > 10
         AND p51.FavoriteCount > 10), 0) as HighlyEngagedAnswer
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.PostId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN PostHistory ph2 ON u.Id = ph2.UserId
LEFT JOIN Posts p2 ON u.Id = p2.OwnerUserId
LEFT JOIN Posts p3 ON u.Id = p3.OwnerUserId
LEFT JOIN Posts p4 ON u.Id = p4.OwnerUserId
LEFT JOIN Posts P5 ON u.Id = P5.OwnerUserId
LEFT JOIN Posts p6 ON u.Id = p6.OwnerUserId
LEFT JOIN Posts p7 ON u.Id = p7.OwnerUserId
LEFT JOIN Posts p8 ON u.Id = p8.OwnerUserId
LEFT JOIN Posts p9 ON u.Id = p9.OwnerUserId
LEFT JOIN Posts p10 ON u.Id = p10.OwnerUserId
LEFT JOIN Posts p11 ON u.Id = p11.OwnerUserId
LEFT JOIN Posts p12 ON u.Id = p12.OwnerUserId
LEFT JOIN Posts p13 ON u.Id = p13.OwnerUserId
LEFT JOIN Posts p14 ON u.Id = p14.OwnerUserId
LEFT JOIN Posts p15 ON u.Id = p15.OwnerUserId
LEFT JOIN Posts p16 ON u.Id = p16.OwnerUserId
LEFT JOIN Posts p17 ON u.Id = p17.OwnerUserId
LEFT JOIN Posts p18 ON u.Id = p18.OwnerUserId
LEFT JOIN Posts p19 ON u.Id = p19.OwnerUserId
LEFT JOIN Posts p20 ON u.Id = p20.OwnerUserId
LEFT JOIN Posts p21 ON u.Id = p21.OwnerUserId
LEFT JOIN Posts p22 ON u.Id = p22.OwnerUserId
LEFT JOIN Posts p23 ON u.Id = p23.OwnerUserId
LEFT JOIN Posts p24 ON u.Id = p24.OwnerUserId
LEFT JOIN Posts p25 ON u.Id = p25.OwnerUserId
LEFT JOIN Posts p26 ON u.Id = p26.OwnerUserId
LEFT JOIN Posts p27 ON u.Id = p27.OwnerUserId
LEFT JOIN Posts p28 ON u.Id = p28.OwnerUserId
LEFT JOIN Posts p29 ON u.Id = p29.OwnerUserId
LEFT JOIN Posts p30 ON u.Id = p30.OwnerUserId
LEFT JOIN Posts p31 ON u.Id = p31.OwnerUserId
LEFT JOIN Posts p32 ON u.Id = p32.OwnerUserId
LEFT JOIN Posts p33 ON u.Id = p33.OwnerUserId
LEFT JOIN Posts p34 ON u.Id = p34.OwnerUserId
LEFT JOIN Posts p35 ON u.Id = p35.OwnerUserId
LEFT JOIN Posts p36 ON u.Id = p36.OwnerUserId
LEFT JOIN Posts p37 ON u.Id = p37.OwnerUserId
LEFT JOIN Posts p38 ON u.Id = p38.OwnerUserId
LEFT JOIN Posts p39 ON u.Id = p39.OwnerUserId
LEFT JOIN Posts p40 ON u.Id = p40.OwnerUserId
LEFT JOIN Posts p41 ON u.Id = p41.OwnerUserId
LEFT JOIN Posts p42 ON u.Id = p42.OwnerUserId
LEFT JOIN Posts p43 ON u.Id = p43.OwnerUserId
LEFT JOIN Posts p44 ON u.Id = p44.OwnerUserId
LEFT JOIN Posts p45 ON u.Id = p45.OwnerUserId
LEFT JOIN Posts p46 ON u.Id = p46.OwnerUserId
LEFT JOIN Posts p47 ON u.Id = p47.OwnerUserId
LEFT JOIN Posts p48 ON u.Id = p48.OwnerUserId
LEFT JOIN Posts p49 ON u.Id = p49.OwnerUserId
LEFT JOIN Posts p50 ON u.Id = p50.OwnerUserId
LEFT JOIN Posts p51 ON u.Id = p51.OwnerUserId
LEFT JOIN Tags t ON p.Id = t.Id
LEFT JOIN Votes pv ON u.Id = pv.UserId
WHERE p.PostTypeId IS NULL OR p.PostTypeId IN (1,2,3,4,5)
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    u.Views, 
    u.UpVotes, 
    u.DownVotes
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY COALESCE(SUM(p.Score), 0) DESC, COUNT(DISTINCT p.Id) DESC;