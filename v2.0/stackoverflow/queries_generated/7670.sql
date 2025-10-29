-- {"query": "7670.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3095} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        NTILE(100) OVER (ORDER BY u.Reputation DESC) as RepPercentile,
        ROW_NUMBER() OVER (PARTITION BY u.AccountId ORDER BY u.CreationDate) as AccountUserRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.AccountId
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        Questions,
        Answers,
        Comments,
        Badges,
        TotalScore,
        LastPostDate,
        PostRank,
        RepPercentile,
        AccountUserRank,
        CASE 
            WHEN TotalPosts > 1000 THEN 'Elite'
            WHEN TotalPosts > 500 THEN 'Veteran'
            WHEN TotalPosts > 100 THEN 'Regular'
            WHEN TotalPosts > 10 THEN 'Newbie'
            ELSE 'Beginner'
        END as UserLevel,
        CASE 
            WHEN RepPercentile <= 1 THEN 'Top 1%'
            WHEN RepPercentile <= 5 THEN 'Top 5%'
            WHEN RepPercentile <= 10 THEN 'Top 10%'
            ELSE 'Below Top 10%'
        END as ReputationTier,
        LAG(Reputation) OVER (ORDER BY TotalPosts DESC) as PrevUserReputation,
        LAG(TotalPosts) OVER (ORDER BY TotalPosts DESC) as PrevUserPosts
    FROM UserActivityStats
    WHERE TotalPosts > 0
),
QuestionStats AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        p.OwnerDisplayName,
        u.DisplayName as OwnerDisplayNameFull,
        DATEDIFF('DAY', p.CreationDate, CURRENT_TIMESTAMP) as AgeInDays,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 10 THEN 'LowVoted'
            ELSE 'NegativelyRated'
        END as VoteCategory,
        CASE 
            WHEN p.AnswerCount = 0 THEN 'Unanswered'
            WHEN p.AnswerCount = 1 THEN 'SingleAnswer'
            WHEN p.AnswerCount BETWEEN 2 AND 5 THEN 'FewAnswers'
            WHEN p.AnswerCount BETWEEN 6 AND 10 THEN 'ManyAnswers'
            ELSE 'ExtremelyAnswered'
        END as AnswerCategory,
        (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) as ActualAnswerCount,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 2) as Upvotes,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 3) as Downvotes,
        (SELECT TOP 1 UserId FROM Votes WHERE PostId = p.Id AND VoteTypeId = 1) as AcceptedAnswerUserId
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        p.OwnerDisplayName,
        p.Body,
        p.LastEditDate,
        CASE 
            WHEN p.Score > 50 THEN 'HighlyVotedAnswer'
            WHEN p.Score > 20 THEN 'ModeratelyVotedAnswer'
            WHEN p.Score > 5 THEN 'LowVotedAnswer'
            ELSE 'NegativelyRatedAnswer'
        END as AnswerQuality,
        DATEDIFF('DAY', p.CreationDate, CURRENT_TIMESTAMP) as AnswerAgeInDays,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 2) as AnswerUpvotes,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 3) as AnswerDownvotes,
        (SELECT TOP 1 Name FROM Badges WHERE UserId = p.OwnerUserId AND Name LIKE '%Answer%') as UserAnswerBadge,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) as AnswerRank,
        PERCENT_RANK() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) as AnswerPercentile
    FROM Posts p
    WHERE p.PostTypeId = 2
),
TagUsageAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count >= 1000 THEN 'PopularTag'
            WHEN t.Count >= 100 THEN 'ModerateTag'
            WHEN t.Count >= 10 THEN 'LessPopularTag'
            ELSE 'RareTag'
        END as TagPopularity,
        (SELECT AVG(p.Score) FROM Posts p JOIN STRING_TO_ARRAY(p.Tags, '><') as tags ON tags = t.TagName WHERE p.PostTypeId = 1) as AvgQuestionScore,
        (SELECT COUNT(DISTINCT OwnerUserId) FROM Posts p JOIN STRING_TO_ARRAY(p.Tags, '><') as tags ON tags = t.TagName WHERE p.PostTypeId = 1) as UniqueQuestionAuthors,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) as PrevTagCount,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as TagRank
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
PostHistoryAggregation AS (
    SELECT 
        ph.PostId,
        COUNT(*) as HistoryEvents,
        MIN(ph.CreationDate) as FirstHistoryEvent,
        MAX(ph.CreationDate) as LastHistoryEvent,
        COUNT(DISTINCT ph.UserId) as UniqueEditors,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1,4,6) THEN ph.UserId END) as TitleEditorCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2,5) THEN ph.UserId END) as BodyEditorCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10,11,12,13) THEN ph.UserId END) as StatusChangeCount,
        STRING_AGG(CASE WHEN ph.PostHistoryTypeId IN (10,11,12,13) THEN ph.Comment END, ', ') as StatusChangesWithReasons,
        DATEDIFF('DAY', MIN(ph.CreationDate), MAX(ph.CreationDate)) as HistorySpanInDays
    FROM PostHistory ph
    GROUP BY ph.PostId
),
PostWithStats AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END as IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END as IsCommunityOwned,
        CASE WHEN EXISTS(SELECT 1 FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) THEN 1 ELSE 0 END as HasAnswers,
        (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) as CommentCount,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId IN (2,3)) as VoteCount,
        (SELECT COUNT(*) FROM PostHistory WHERE PostId = p.Id) as HistoryCount,
        (SELECT MAX(CreationDate) FROM Comments WHERE PostId = p.Id) as LastCommentDate,
        (SELECT MIN(CreationDate) FROM PostHistory WHERE PostId = p.Id) as FirstHistoryDate,
        (SELECT COUNT(DISTINCT UserId) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 2) as UpvoterCount,
        (SELECT COUNT(DISTINCT UserId) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 3) as DownvoterCount,
        (SELECT COUNT(*) FROM Badges WHERE UserId = p.OwnerUserId AND Name LIKE '%Answer%') as UserAnswerBadgeCount,
        CASE 
            WHEN p.Score > 100 THEN 'Popular'
            WHEN p.Score > 50 THEN 'ModeratelyPopular'
            WHEN p.Score > 10 THEN 'MinorPopularity'
            ELSE 'Uncertain'
        END as PopularityLevel,
        CASE 
            WHEN p.CreationDate >= DATEADD('MONTH', -3, CURRENT_TIMESTAMP) THEN 'Recent'
            WHEN p.CreationDate >= DATEADD('MONTH', -12, CURRENT_TIMESTAMP) THEN 'LastYear'
            WHEN p.CreationDate >= DATEADD('YEAR', -3, CURRENT_TIMESTAMP) THEN 'RecentHistory'
            ELSE 'Historical'
        END as TimeCategory,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) as PrevScore,
        ROUND(AVG(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW), 2) as ScoreMovingAvg,
        p.OwnerUserId
    FROM Posts p
    WHERE p.Id IS NOT NULL
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.Questions,
    tu.Answers,
    tu.Comments,
    tu.Badges,
    tu.TotalScore,
    tu.LastPostDate,
    tu.PostRank,
    tu.RepPercentile,
    tu.AccountUserRank,
    tu.UserLevel,
    tu.ReputationTier,
    tu.PrevUserReputation,
    tu.PrevUserPosts,
    qs.QuestionId,
    qs.Title as QuestionTitle,
    qs.Score as QuestionScore,
    qs.ViewCount as QuestionViewCount,
    qs.AnswerCount as QuestionAnswerCount,
    qs.CommentCount as QuestionCommentCount,
    qs.FavoriteCount as QuestionFavoriteCount,
    qs.CreationDate as QuestionCreationDate,
    qs.OwnerUserId,
    qs.OwnerDisplayNameFull,
    qs.AgeInDays,
    qs.VoteCategory,
    qs.AnswerCategory,
    qs.ActualAnswerCount,
    qs.Upvotes,
    qs.Downvotes,
    qs.AcceptedAnswerUserId,
    asa.AnswerId,
    asa.QuestionId as AnswerQuestionId,
    asa.Score as AnswerScore,
    asa.CreationDate as AnswerCreationDate,
    asa.OwnerUserId as AnswerOwnerUserId,
    asa.OwnerDisplayName,
    asa.Body as AnswerBody,
    asa.AnswerAgeInDays,
    asa.AnswerUpvotes,
    asa.AnswerDownvotes,
    asa.UserAnswerBadge,
    asa.AnswerRank,
    asa.AnswerPercentile,
    ta.TagName,
    ta.TagCount,
    ta.TagPopularity,
    ta.AvgQuestionScore,
    ta.UniqueQuestionAuthors,
    ta.PrevTagCount,
    ta.TagRank,
    pha.HistoryEvents,
    pha.FirstHistoryEvent,
    pha.LastHistoryEvent,
    pha.UniqueEditors,
    pha.TitleEditorCount,
    pha.BodyEditorCount,
    pha.StatusChangeCount,
    pha.StatusChangesWithReasons,
    pha.HistorySpanInDays,
    ps.PostId,
    ps.PostTypeId,
    ps.Title as PostTitle,
    ps.Score as PostScore,
    ps.ViewCount as PostViewCount,
    ps.CreationDate as PostCreationDate,
    ps.IsClosed,
    ps.IsCommunityOwned,
    ps.HasAnswers,
    ps.CommentCount as PostCommentCount,
    ps.VoteCount,
    ps.HistoryCount,
    ps.LastCommentDate,
    ps.FirstHistoryDate,
    ps.UpvoterCount,
    ps.DownvoterCount,
    ps.UserAnswerBadgeCount,
    ps.PopularityLevel,
    ps.TimeCategory,
    ps.PrevScore,
    ps.ScoreMovingAvg,
    ps.OwnerUserId as PostOwnerUserId,
    CASE 
        WHEN tu.Reputation > 10000 AND tu.TotalPosts > 1000 THEN 'EliteContributor'
        WHEN tu.Reputation > 5000 AND tu.TotalPosts > 500 THEN 'VeteranContributor'
        WHEN tu.Reputation > 1000 AND tu.TotalPosts > 100 THEN 'RegularContributor'
        WHEN tu.Reputation > 500 AND tu.TotalPosts > 10 THEN 'NewContributor'
        ELSE 'BeginningContributor'
    END as ContributorType
FROM TopUsers tu
LEFT JOIN QuestionStats qs ON EXISTS(SELECT 1 FROM Posts WHERE Id = qs.QuestionId AND OwnerUserId = tu.UserId)
LEFT JOIN AnswerStats asa ON EXISTS(SELECT 1 FROM Posts WHERE Id = asa.AnswerId AND OwnerUserId = tu.UserId)
LEFT JOIN TagUsageAnalysis ta ON EXISTS(SELECT 1 FROM Posts p JOIN STRING_TO_ARRAY(p.Tags, '><') as tags ON tags = ta.TagName WHERE p.OwnerUserId = tu.UserId AND p.PostTypeId = 1)
LEFT JOIN PostHistoryAggregation pha ON EXISTS(SELECT 1 FROM Posts WHERE Id = pha.PostId AND OwnerUserId = tu.UserId)
LEFT JOIN PostWithStats ps ON EXISTS(SELECT 1 FROM Posts WHERE Id = ps.PostId AND OwnerUserId = tu.UserId)
WHERE 
    (tu.TotalPosts > 50 OR qs.QuestionId IS NOT NULL OR asa.AnswerId IS NOT NULL OR ta.TagName IS NOT NULL OR ps.PostId IS NOT NULL)
    AND NOT (tu.Reputation = 1 AND tu.TotalPosts = 1)
    AND tu.Reputation > 0
ORDER BY 
    tu.Reputation DESC,
    tu.TotalPosts DESC,
    qs.Score DESC,
    asa.Score DESC,
    ta.TagCount DESC,
    ps.Score DESC
LIMIT 5000;