-- {"query": "7137.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2168} 
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
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as UserLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without Accepted Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostCategory,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Moderately Voted'
            WHEN p.Score > 0 THEN 'Low Voted'
            ELSE 'No Votes'
        END as VoteStatus,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevScore,
        LAG(p.ViewCount, 1) OVER (ORDER BY p.CreationDate) as PrevViewCount
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'::timestamp
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.WikiPostId,
        t.ExcerptPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as PopularityLevel,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as PopularityRank,
        AVG(t.Count) OVER () as AvgTagCount
    FROM Tags t
    WHERE t.Count > 0
),
VotingPatterns AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        COUNT(*) as VoteCount,
        MAX(v.CreationDate) as LastVoteDate,
        AVG(v.CreationDate) as AvgVoteDate,
        STRING_AGG(DISTINCT u.DisplayName, ', ' ORDER BY u.DisplayName) as VotedByUsers,
        CASE 
            WHEN v.VoteTypeId IN (2, 3) THEN 'Reputation Votes'
            WHEN v.VoteTypeId IN (4, 12) THEN 'Moderation Votes'
            WHEN v.VoteTypeId IN (8, 9) THEN 'Bounty Votes'
            ELSE 'Other Votes'
        END as VoteCategory
    FROM Votes v
    LEFT JOIN Users u ON v.UserId = u.Id
    WHERE v.CreationDate >= '2020-01-01'::timestamp
    GROUP BY v.PostId, v.VoteTypeId
),
CombinedAnalysis AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.AvgPostScore,
        us.UserLevel,
        us.ReputationRank,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.PostCategory,
        pa.VoteStatus,
        pa.ScoreRank,
        pa.ViewRank,
        ta.TagName,
        ta.TagCount,
        ta.PopularityLevel,
        vp.VoteTypeId,
        vp.VoteCount,
        vp.VoteCategory,
        CASE 
            WHEN pa.Score > 0 AND pa.AnswerCount > 0 THEN pa.Score * pa.AnswerCount
            ELSE 0
        END as EngagementScore,
        CASE 
            WHEN pa.CreationDate >= '2022-01-01' THEN 'Recent'
            WHEN pa.CreationDate >= '2020-01-01' THEN 'Modern'
            ELSE 'Historical'
        END as TimePeriod,
        COALESCE(pa.ParentId, 0) as ParentId,
        COALESCE(vp.VoteCount, 0) as TotalVotes
    FROM UserStats us
    INNER JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
    LEFT JOIN VotingPatterns vp ON pa.PostId = vp.PostId
    LEFT JOIN (
        SELECT 
            p.Id as PostId,
            t.TagName
        FROM Posts p
        JOIN unnest(string_to_array(trim(p.Tags, '<>'), '><')) as t(TagName) ON true
        WHERE p.Tags IS NOT NULL AND p.Tags != ''
    ) tag_joined ON pa.PostId = tag_joined.PostId
    LEFT JOIN TagAnalysis ta ON tag_joined.TagName = ta.TagName
    WHERE us.PostCount > 0
),
FinalAggregation AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        AvgPostScore,
        UserLevel,
        ReputationRank,
        COUNT(DISTINCT PostId) as TotalPosts,
        AVG(Score) as AvgPostScoreAll,
        SUM(Score) as TotalScore,
        MAX(MaxScore) as MaxScore,
        SUM(EngagementScore) as TotalEngagement,
        STRING_AGG(DISTINCT PostCategory, ' | ' ORDER BY PostCategory) as PostCategories,
        STRING_AGG(DISTINCT VoteCategory, ' | ' ORDER BY VoteCategory) as VoteCategories,
        STRING_AGG(DISTINCT TagName, ' | ' ORDER BY TagName) as TaggedTopics,
        SUM(CASE WHEN VoteCount > 0 THEN 1 ELSE 0 END) as PostsWithVotes,
        AVG(TotalVotes) as AvgVotesPerPost,
        COUNT(DISTINCT CASE WHEN VoteCategory = 'Reputation Votes' THEN PostId END) as ReputationVotedPosts,
        COUNT(DISTINCT CASE WHEN VoteCategory = 'Moderation Votes' THEN PostId END) as ModerationVotedPosts,
        COUNT(DISTINCT CASE WHEN VoteCategory = 'Bounty Votes' THEN PostId END) as BountyVotedPosts,
        CASE 
            WHEN AVG(PostScore) > 10 THEN 'Highly Engaging'
            WHEN AVG(PostScore) > 5 THEN 'Moderately Engaging'
            ELSE 'Low Engagement'
        END as EngagementLevel
    FROM (
        SELECT 
            ca.UserId,
            ca.DisplayName,
            ca.Reputation,
            ca.PostCount,
            ca.CommentCount,
            ca.BadgeCount,
            ca.AvgPostScore,
            ca.UserLevel,
            ca.ReputationRank,
            ca.PostId,
            ca.Score,
            ca.PostCategory,
            ca.VoteCategory,
            ca.TagName,
            ca.VoteCount,
            ca.EngagementScore,
            ca.TotalVotes,
            ca.Score as PostScore,
            MAX(ca.Score) OVER (PARTITION BY ca.UserId) as MaxScore
        FROM CombinedAnalysis ca
    ) subquery
    GROUP BY UserId, DisplayName, Reputation, PostCount, CommentCount, BadgeCount, AvgPostScore, UserLevel, ReputationRank
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.PostCount,
    fa.CommentCount,
    fa.BadgeCount,
    fa.AvgPostScore,
    fa.UserLevel,
    fa.ReputationRank,
    fa.TotalPosts,
    fa.AvgPostScoreAll,
    fa.TotalScore,
    fa.MaxScore,
    fa.TotalEngagement,
    fa.PostCategories,
    fa.VoteCategories,
    fa.TaggedTopics,
    fa.PostsWithVotes,
    fa.AvgVotesPerPost,
    fa.ReputationVotedPosts,
    fa.ModerationVotedPosts,
    fa.BountyVotedPosts,
    fa.EngagementLevel,
    CASE 
        WHEN fa.ReputationRank <= 10 THEN 'Top 10'
        WHEN fa.ReputationRank <= 50 THEN 'Top 50'
        WHEN fa.ReputationRank <= 100 THEN 'Top 100'
        ELSE 'Below Top 100'
    END as RankingTier,
    ROUND((fa.AvgPostScoreAll * 100.0 / NULLIF(fa.Reputation, 0)), 2) as ScorePerRepRatio,
    ROUND((fa.TotalScore * 1.0 / NULLIF(fa.TotalPosts, 0)), 2) as AvgScorePerPost,
    (SELECT COUNT(*) FROM FinalAggregation fa2 WHERE fa2.Reputation > fa.Reputation) as HigherReputationUsers,
    (SELECT COUNT(*) FROM FinalAggregation fa3 WHERE fa3.Reputation < fa.Reputation) as LowerReputationUsers
FROM FinalAggregation fa
WHERE fa.PostCount > 0
AND (fa.Reputation > 1000 OR fa.BadgeCount > 5 OR fa.TotalPosts > 10)
ORDER BY fa.Reputation DESC
LIMIT 1000
OFFSET 100;