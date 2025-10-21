-- {"query": "29083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2391} 
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
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LatestPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
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
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.AnswerCount > 0 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered with Accepted'
            WHEN p.AnswerCount > 0 THEN 'Answered'
            WHEN p.AnswerCount = 0 THEN 'Unanswered'
            ELSE 'Unknown'
        END as AnswerStatus,
        COALESCE(p.Body, '') as Body,
        COALESCE(LENGTH(p.Body), 0) as BodyLength,
        CASE 
            WHEN p.Body LIKE '%<code>%</code>%' THEN 1
            ELSE 0
        END as HasCode,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as UpvoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as DownvoteCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCountActual,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateLinkCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
ComplexPostAnalysis AS (
    SELECT 
        pc.PostId,
        pc.Title,
        pc.Score,
        pc.ViewCount,
        pc.AnswerCount,
        pc.CommentCount,
        pc.FavoriteCount,
        pc.CreationDate,
        pc.OwnerUserId,
        pc.PostType,
        pc.AnswerStatus,
        pc.HasCode,
        pc.UpvoteCount,
        pc.DownvoteCount,
        pc.CommentCountActual,
        pc.DuplicateLinkCount,
        pc.UserPostRank,
        RANK() OVER (ORDER BY pc.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY pc.ViewCount DESC) as ViewRank,
        NTILE(4) OVER (ORDER BY pc.Score) as ScoreQuartile,
        LAG(pc.Score, 1) OVER (ORDER BY pc.CreationDate) as PreviousScore,
        LEAD(pc.Score, 1) OVER (ORDER BY pc.CreationDate) as NextScore,
        AVG(pc.Score) OVER (PARTITION BY pc.OwnerUserId) as UserAvgScore,
        MAX(pc.Score) OVER (PARTITION BY pc.OwnerUserId) as UserMaxScore,
        MIN(pc.Score) OVER (PARTITION BY pc.OwnerUserId) as UserMinScore,
        (pc.Score - LAG(pc.Score, 1) OVER (ORDER BY pc.CreationDate)) as ScoreChange,
        CASE 
            WHEN pc.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
            WHEN pc.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Average'
            ELSE 'Average'
        END as ScoreCategory,
        CASE 
            WHEN pc.AnswerCount > 0 THEN 
                CASE 
                    WHEN pc.Score > 0 AND pc.AnswerCount = 0 THEN 'High Score, No Answers'
                    WHEN pc.Score <= 0 AND pc.AnswerCount = 0 THEN 'Low Score, No Answers'
                    WHEN pc.Score > 0 AND pc.AnswerCount > 0 THEN 'High Score, Has Answers'
                    ELSE 'Low Score, Has Answers'
                END
            ELSE 'No Answers'
        END as ScoreAnswerStatus,
        CASE 
            WHEN pc.HasCode = 1 AND pc.ViewCount > 100 THEN 'Code Heavy, Popular'
            WHEN pc.HasCode = 1 AND pc.ViewCount <= 100 THEN 'Code Heavy, Less Popular'
            WHEN pc.HasCode = 0 AND pc.ViewCount > 100 THEN 'No Code, Popular'
            ELSE 'No Code, Less Popular'
        END as CodeViewPattern
    FROM PostComplexity pc
),
UserPerformance AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.Views,
        us.UpVotes,
        us.DownVotes,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.AvgPostScore,
        us.LatestPostDate,
        us.AllTags,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC) as ReputationRank,
        RANK() OVER (ORDER BY us.PostCount DESC) as PostCountRank,
        DENSE_RANK() OVER (ORDER BY us.CommentCount DESC) as CommentCountRank,
        CASE 
            WHEN us.PostCount > 50 AND us.Reputation > 5000 THEN 'Highly Active Contributor'
            WHEN us.PostCount BETWEEN 10 AND 50 AND us.Reputation BETWEEN 1000 AND 5000 THEN 'Active Contributor'
            WHEN us.PostCount < 10 AND us.Reputation < 1000 THEN 'New Contributor'
            ELSE 'Regular Contributor'
        END as ContributionLevel,
        CASE 
            WHEN us.BadgeCount > 10 THEN 'Badge Collector'
            WHEN us.BadgeCount BETWEEN 5 AND 10 THEN 'Moderate Badge Holder'
            WHEN us.BadgeCount < 5 THEN 'Occasional Badger'
            ELSE 'Badge Enthusiast'
        END as BadgeStatus,
        COUNT(*) OVER () as TotalUsers,
        AVG(us.Reputation) OVER () as AvgReputation
    FROM UserStats us
),
FinalAnalysis AS (
    SELECT 
        up.UserId,
        up.DisplayName,
        up.Reputation,
        up.Views,
        up.PostCount,
        up.CommentCount,
        up.BadgeCount,
        up.AvgPostScore,
        up.LatestPostDate,
        up.ContributionLevel,
        up.BadgeStatus,
        up.ReputationRank,
        up.PostCountRank,
        up.CommentCountRank,
        CASE 
            WHEN up.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'Above Average Reputation'
            WHEN up.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'Below Average Reputation'
            ELSE 'Average Reputation'
        END as ReputationStatus,
        CASE 
            WHEN up.PostCount > (SELECT AVG(PostCount) FROM UserStats) THEN 'Above Average Post Count'
            WHEN up.PostCount < (SELECT AVG(PostCount) FROM UserStats) THEN 'Below Average Post Count'
            ELSE 'Average Post Count'
        END as PostCountStatus,
        (SELECT COUNT(*) FROM ComplexPostAnalysis cpa WHERE cpa.OwnerUserId = up.UserId AND cpa.Score > 0) as PositiveScorePosts,
        (SELECT COUNT(*) FROM ComplexPostAnalysis cpa WHERE cpa.OwnerUserId = up.UserId AND cpa.AnswerCount > 0) as AnsweredPosts,
        (SELECT COUNT(*) FROM ComplexPostAnalysis cpa WHERE cpa.OwnerUserId = up.UserId AND cpa.Score > 10) as HighScorePosts,
        (SELECT STRING_AGG(DISTINCT pc.PostType, ', ') FROM ComplexPostAnalysis pc WHERE pc.OwnerUserId = up.UserId) as PostTypesCreated,
        (SELECT STRING_AGG(DISTINCT pc.AnswerStatus, ', ') FROM ComplexPostAnalysis pc WHERE pc.OwnerUserId = up.UserId) as AnswerStatuses
    FROM UserPerformance up
    WHERE up.BadgeCount > 0
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.Views,
    fa.PostCount,
    fa.CommentCount,
    fa.BadgeCount,
    fa.AvgPostScore,
    fa.LatestPostDate,
    fa.ContributionLevel,
    fa.BadgeStatus,
    fa.ReputationRank,
    fa.PostCountRank,
    fa.CommentCountRank,
    fa.ReputationStatus,
    fa.PostCountStatus,
    fa.PositiveScorePosts,
    fa.AnsweredPosts,
    fa.HighScorePosts,
    fa.PostTypesCreated,
    fa.AnswerStatuses,
    CASE 
        WHEN fa.PostCount > 20 AND fa.BadgeCount > 5 THEN 'Productive Contributor'
        WHEN fa.PostCount BETWEEN 5 AND 20 AND fa.BadgeCount BETWEEN 2 AND 5 THEN 'Moderate Contributor'
        WHEN fa.PostCount < 5 AND fa.BadgeCount < 2 THEN 'Beginner Contributor'
        ELSE 'Contributor'
    END as ContributionTier,
    CASE 
        WHEN fa.Reputation > 5000 AND fa.PostCount > 10 THEN 'Established Expert'
        WHEN fa.Reputation BETWEEN 1000 AND 5000 AND fa.PostCount BETWEEN 5 AND 10 THEN 'Experienced Contributor'
        WHEN fa.Reputation < 1000 AND fa.PostCount < 5 THEN 'Newbie'
        ELSE 'Professional Contributor'
    END as ExpertiseLevel,
    ROW_NUMBER() OVER (ORDER BY fa.Reputation DESC, fa.PostCount DESC) as CombinedRank,
    RANK() OVER (ORDER BY fa.AvgPostScore DESC, fa.Reputation DESC) as ScoreReputationRank,
    DENSE_RANK() OVER (ORDER BY (fa.PositiveScorePosts + fa.AnsweredPosts + fa.HighScorePosts) DESC) as ActivityRank,
    (fa.Reputation - (SELECT AVG(Reputation) FROM Users)) as ReputationDeviation,
    (fa.PostCount - (SELECT AVG(PostCount) FROM UserStats)) as PostCountDeviation,
    (fa.BadgeCount - (SELECT AVG(BadgeCount) FROM UserStats)) as BadgeCountDeviation
FROM FinalAnalysis fa
WHERE fa.Reputation > 1000
    AND fa.PostCount > 0
    AND fa.CommentCount >= 0
    AND fa.BadgeCount > 0
    AND LENGTH(fa.DisplayName) > 0
ORDER BY fa.Reputation DESC, fa.PostCount DESC, fa.CommentCount DESC
LIMIT 1000;