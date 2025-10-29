-- {"query": "7717.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2887} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FILTER (WHERE p.Tags IS NOT NULL) as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        LastPostDate,
        AllTags,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByReputation,
        RANK() OVER (ORDER BY PostCount DESC) as RankByPostCount
    FROM UserStats
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostCategory,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Well Voted'
            WHEN p.Score > 0 THEN 'Moderately Voted'
            ELSE 'Low or No Votes'
        END as VoteLevel,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as EngagementCount,
        (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) as AnswerCountReal,
        (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) as CommentCountReal,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId IN (2, 3)) as VoteCountReal,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 5) as FavoriteCountReal,
        (SELECT STRING_AGG(Name, ', ') FROM Badges WHERE UserId = p.OwnerUserId) as UserBadges,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags LIKE '%<%' THEN 
                STRING_AGG(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ')
            ELSE NULL 
        END as CleanedTags,
        (SELECT AVG(Score) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2) as AvgAnswerScore,
        (SELECT MAX(Score) FROM Posts p3 WHERE p3.ParentId = p.Id AND p3.PostTypeId = 2) as MaxAnswerScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
CombinedAnalysis AS (
    SELECT 
        ta.PostId,
        ta.Title,
        ta.Score,
        ta.ViewCount,
        ta.CreationDate,
        ta.OwnerUserId,
        ta.ParentId,
        ta.PostTypeId,
        ta.Tags,
        ta.AnswerCount,
        ta.CommentCount,
        ta.FavoriteCount,
        ta.PostCategory,
        ta.VoteLevel,
        ta.EnagementCount,
        ta.AnswerCountReal,
        ta.CommentCountReal,
        ta.VoteCountReal,
        ta.FavoriteCountReal,
        ta.UserBadges,
        ta.CleanedTags,
        ta.AvgAnswerScore,
        ta.MaxAnswerScore,
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.CommentCount as UserCommentCount,
        tu.BadgeCount,
        tu.LastPostDate,
        tu.AllTags,
        tu.RankByReputation,
        tu.RankByPostCount,
        CASE 
            WHEN tu.Reputation >= 10000 THEN 'Elite'
            WHEN tu.Reputation >= 5000 THEN 'Expert'
            WHEN tu.Reputation >= 1000 THEN 'Advanced'
            ELSE 'Beginner'
        END as UserTier,
        ROW_NUMBER() OVER (PARTITION BY ta.OwnerUserId ORDER BY ta.Score DESC) as UserPostRanking,
        LAG(ta.Title) OVER (PARTITION BY ta.OwnerUserId ORDER BY ta.CreationDate) as PreviousPostTitle,
        LEAD(ta.Title) OVER (PARTITION BY ta.OwnerUserId ORDER BY ta.CreationDate) as NextPostTitle,
        SUM(ta.Score) OVER (PARTITION BY ta.OwnerUserId ORDER BY ta.CreationDate ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) as ScoreMovingAverage,
        NTILE(5) OVER (ORDER BY ta.Score) as ScoreQuintile
    FROM PostAnalysis ta
    JOIN TopUsers tu ON ta.OwnerUserId = tu.UserId
    WHERE ta.OwnerUserId IS NOT NULL
),
ComplexQueries AS (
    SELECT 
        ca.PostId,
        ca.Title,
        ca.Score,
        ca.ViewCount,
        ca.CreationDate,
        ca.OwnerUserId,
        ca.ParentId,
        ca.PostTypeId,
        ca.Tags,
        ca.AnswerCount,
        ca.CommentCount,
        ca.FavoriteCount,
        ca.PostCategory,
        ca.VoteLevel,
        ca.EnagementCount,
        ca.AnswerCountReal,
        ca.CommentCountReal,
        ca.VoteCountReal,
        ca.FavoriteCountReal,
        ca.UserBadges,
        ca.CleanedTags,
        ca.AvgAnswerScore,
        ca.MaxAnswerScore,
        ca.UserId,
        ca.DisplayName,
        ca.Reputation,
        ca.PostCount,
        ca.UserCommentCount,
        ca.BadgeCount,
        ca.LastPostDate,
        ca.AllTags,
        ca.RankByReputation,
        ca.RankByPostCount,
        ca.UserTier,
        ca.UserPostRanking,
        ca.PreviousPostTitle,
        ca.NextPostTitle,
        ca.ScoreMovingAverage,
        ca.ScoreQuintile,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = ca.OwnerUserId AND CreationDate >= DATEADD(month, -6, GETDATE())) as RecentPostsThisYear,
        (SELECT STRING_AGG(Title, '; ') FROM Posts WHERE ParentId = ca.PostId AND PostTypeId = 2) as AnswerTitles,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = ca.PostId AND ph.PostHistoryTypeId = 10) as CloseCount,
        (SELECT MAX(CreationDate) FROM PostHistory ph WHERE ph.PostId = ca.PostId) as LastHistoryDate,
        (SELECT AVG(Score) FROM Posts p4 WHERE p4.OwnerUserId = ca.OwnerUserId AND p4.PostTypeId = 1) as UserQuestionAvgScore,
        CASE 
            WHEN ca.PostTypeId = 2 AND ca.ParentId IS NOT NULL THEN 
                (SELECT Title FROM Posts WHERE Id = ca.ParentId)
            ELSE NULL
        END as QuestionTitle,
        ABS(ca.Score - (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = ca.OwnerUserId)) as ScoreDeviationFromUserAvg,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ca.PostId AND v.VoteTypeId = 2) as Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ca.PostId AND v.VoteTypeId = 3) as Downvotes,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = ca.PostId) as LinkCount,
        CASE 
            WHEN ca.CreationDate > DATEADD(day, -7, GETDATE()) THEN 'This Week'
            WHEN ca.CreationDate > DATEADD(day, -30, GETDATE()) THEN 'This Month'
            ELSE 'Older'
        END as Recency
    FROM CombinedAnalysis ca
)
SELECT 
    cq.PostId,
    cq.Title,
    cq.Score,
    cq.ViewCount,
    cq.CreationDate,
    cq.OwnerUserId,
    cq.ParentId,
    cq.PostTypeId,
    cq.Tags,
    cq.AnswerCount,
    cq.CommentCount,
    cq.FavoriteCount,
    cq.PostCategory,
    cq.VoteLevel,
    cq.EnagementCount,
    cq.AnswerCountReal,
    cq.CommentCountReal,
    cq.VoteCountReal,
    cq.FavoriteCountReal,
    cq.UserBadges,
    cq.CleanedTags,
    cq.AvgAnswerScore,
    cq.MaxAnswerScore,
    cq.UserId,
    cq.DisplayName,
    cq.Reputation,
    cq.PostCount,
    cq.UserCommentCount,
    cq.BadgeCount,
    cq.LastPostDate,
    cq.AllTags,
    cq.RankByReputation,
    cq.RankByPostCount,
    cq.UserTier,
    cq.UserPostRanking,
    cq.PreviousPostTitle,
    cq.NextPostTitle,
    cq.ScoreMovingAverage,
    cq.ScoreQuintile,
    cq.RecentPostsThisYear,
    cq.AnswerTitles,
    cq.CloseCount,
    cq.LastHistoryDate,
    cq.UserQuestionAvgScore,
    cq.QuestionTitle,
    cq.ScoreDeviationFromUserAvg,
    cq.Upvotes,
    cq.Downvotes,
    cq.LinkCount,
    cq.Recency,
    CASE 
        WHEN cq.Reputation > 5000 AND cq.RecentPostsThisYear > 5 THEN 'Active High Reputation'
        WHEN cq.Reputation > 1000 AND cq.RecentPostsThisYear > 2 THEN 'Active Medium Reputation'
        ELSE 'Passive User'
    END as UserActivityStatus,
    ROUND(cq.Score * 1.0 / NULLIF(cq.ViewCount, 0), 4) as ScorePerViewRatio,
    CASE 
        WHEN cq.Score > 100 AND cq.ViewCount > 1000 THEN 'High Impact'
        WHEN cq.Score > 50 AND cq.ViewCount > 500 THEN 'Medium Impact'
        ELSE 'Low Impact'
    END as ImpactCategory,
    'PostId_' + CAST(cq.PostId AS VARCHAR(20)) as SyntheticPostId,
    (SELECT TOP 1 ph.Comment FROM PostHistory ph WHERE ph.PostId = cq.PostId AND ph.PostHistoryTypeId = 10 ORDER BY ph.CreationDate DESC) as RecentCloseComment,
    (SELECT DISTINCT ph.UserId FROM PostHistory ph WHERE ph.PostId = cq.PostId AND ph.UserId IS NOT NULL) as LastEditorUserId,
    COALESCE(cq.AnswerTitles, 'No Answers') as AnswerSummary,
    COALESCE(cq.QuestionTitle, 'No Parent') as QuestionContext,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = cq.UserId AND b.Date >= DATEADD(year, -1, GETDATE())) as RecentBadgesThisYear
FROM ComplexQueries cq
WHERE cq.Score > 0 AND cq.Reputation > 0
UNION ALL
SELECT 
    -1 as PostId,
    'Overall Summary' as Title,
    NULL as Score,
    SUM(cq.ViewCount) as ViewCount,
    NULL as CreationDate,
    NULL as OwnerUserId,
    NULL as ParentId,
    NULL as PostTypeId,
    NULL as Tags,
    NULL as AnswerCount,
    NULL as CommentCount,
    NULL as FavoriteCount,
    NULL as PostCategory,
    NULL as VoteLevel,
    NULL as EnagementCount,
    NULL as AnswerCountReal,
    NULL as CommentCountReal,
    NULL as VoteCountReal,
    NULL as FavoriteCountReal,
    NULL as UserBadges,
    NULL as CleanedTags,
    AVG(cq.AvgAnswerScore) as AvgAnswerScore,
    MAX(cq.MaxAnswerScore) as MaxAnswerScore,
    NULL as UserId,
    'Aggregate Analysis' as DisplayName,
    NULL as Reputation,
    COUNT(DISTINCT cq.OwnerUserId) as PostCount,
    NULL as UserCommentCount,
    NULL as BadgeCount,
    NULL as LastPostDate,
    NULL as AllTags,
    NULL as RankByReputation,
    NULL as RankByPostCount,
    NULL as UserTier,
    NULL as UserPostRanking,
    NULL as PreviousPostTitle,
    NULL as NextPostTitle,
    NULL as ScoreMovingAverage,
    NULL as ScoreQuintile,
    NULL as RecentPostsThisYear,
    NULL as AnswerTitles,
    NULL as CloseCount,
    NULL as LastHistoryDate,
    NULL as UserQuestionAvgScore,
    NULL as QuestionTitle,
    NULL as ScoreDeviationFromUserAvg,
    NULL as Upvotes,
    NULL as Downvotes,
    NULL as LinkCount,
    NULL as Recency,
    NULL as UserActivityStatus,
    NULL as ScorePerViewRatio,
    NULL as ImpactCategory,
    'Summary' as SyntheticPostId,
    NULL as RecentCloseComment,
    NULL as LastEditorUserId,
    NULL as AnswerSummary,
    NULL as QuestionContext,
    NULL as RecentBadgesThisYear
FROM ComplexQueries cq
WHERE cq.Score > 0
GROUP BY 'Overall Summary'
ORDER BY cq.Score DESC, cq.ViewCount DESC, cq.Reputation DESC
LIMIT 1000;