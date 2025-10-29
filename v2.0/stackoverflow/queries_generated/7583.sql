-- {"query": "7583.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2938} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        AVG(p.Score) as AvgScore,
        COUNT(DISTINCT c.Id) as CommentCount,
        STRING_AGG(DISTINCT COALESCE(u.Location, 'Unknown'), ', ') as Locations,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        DENSE_RANK() OVER (ORDER BY u.Views DESC) as ViewRank,
        CASE 
            WHEN u.Reputation >= 100000 THEN 'Legendary'
            WHEN u.Reputation >= 10000 THEN 'Master'
            WHEN u.Reputation >= 1000 THEN 'Expert'
            WHEN u.Reputation >= 100 THEN 'Novice'
            ELSE 'Beginner'
        END as ReputationTier,
        ROW_NUMBER() OVER (PARTITION BY u.AccountId ORDER BY u.CreationDate) as AccountMemberSequence
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId, u.Location
),
PostMetrics AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        p.LastActivityDate,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Question'
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN 'Answer'
            ELSE 'Other'
        END as PostCategory,
        CASE 
            WHEN p.LastActivityDate >= CURRENT_TIMESTAMP - INTERVAL '7 days' THEN 'Active'
            WHEN p.LastActivityDate >= CURRENT_TIMESTAMP - INTERVAL '30 days' THEN 'Recently Active'
            WHEN p.LastActivityDate >= CURRENT_TIMESTAMP - INTERVAL '90 days' THEN 'Inactive'
            ELSE 'Very Inactive'
        END as ActivityStatus,
        EXTRACT(YEAR FROM p.CreationDate) as PostYear,
        EXTRACT(MONTH FROM p.CreationDate) as PostMonth,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'Negative'
        END as ScoreCategory,
        ARRAY_LENGTH(STRING_TO_ARRAY(p.Tags, '<'), '<') as TagCount,
        TRIM(BOTH '<' FROM p.Tags) as CleanTags,
        COALESCE(p.AnswerCount, 0) as ActualAnswerCount,
        COALESCE(p.CommentCount, 0) as ActualCommentCount
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
EngagementAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.ParentId,
        CASE 
            WHEN p.Views > 0 THEN (p.Score * 100.0 / p.Views)
            ELSE 0
        END as ScoreToViewRatio,
        CASE 
            WHEN p.AnswerCount > 0 THEN (p.Score * 1.0 / p.AnswerCount)
            ELSE 0
        END as ScorePerAnswer,
        CASE 
            WHEN p.CommentCount > 0 THEN (p.Score * 1.0 / p.CommentCount)
            ELSE 0
        END as ScorePerComment,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as NewnessRank
    FROM PostMetrics p
    WHERE p.PostTypeId IN (1, 2)
),
UserPostPerformance AS (
    SELECT 
        us.UserId,
        us.Reputation,
        us.PostCount,
        us.QuestionCount,
        us.AnswerCount,
        us.BadgeCount,
        us.TotalScore,
        us.AvgScore,
        us.ReputationRank,
        us.ViewRank,
        us.ReputationTier,
        ep.PostId,
        ep.Score as PostScore,
        ep.ViewCount as PostViewCount,
        ep.AnswerCount as PostAnswerCount,
        ep.CommentCount as PostCommentCount,
        ep.ScoreToViewRatio,
        ep.ScorePerAnswer,
        ep.ScorePerComment,
        ep.ScoreRank,
        ep.ViewRank as PostViewRank,
        ep.NewnessRank,
        CASE 
            WHEN ep.ScoreRank <= 100 THEN 'Top 100'
            WHEN ep.ScoreRank <= 500 THEN 'Top 500'
            WHEN ep.ScoreRank <= 1000 THEN 'Top 1000'
            ELSE 'Lower'
        END as ScoringTier,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ep.PostId AND v.VoteTypeId = 2), 0
        ) as UpVoteCount,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ep.PostId AND v.VoteTypeId = 3), 0
        ) as DownVoteCount,
        CASE 
            WHEN ep.PostScore > 10 AND ep.PostViewCount > 100 THEN 'Popular'
            WHEN ep.PostScore > 5 AND ep.PostViewCount > 50 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityCategory
    FROM UserStats us
    JOIN EngagementAnalysis ep ON us.UserId = ep.OwnerUserId
    WHERE us.AccountMemberSequence = 1
)
SELECT 
    COUNT(*) as TotalUsers,
    COUNT(DISTINCT CASE WHEN upp.ReputationTier = 'Legendary' THEN upp.UserId END) as LegendaryUsers,
    COUNT(DISTINCT CASE WHEN upp.ReputationTier = 'Master' THEN upp.UserId END) as MasterUsers,
    COUNT(DISTINCT CASE WHEN upp.ReputationTier = 'Expert' THEN upp.UserId END) as ExpertUsers,
    COUNT(DISTINCT CASE WHEN upp.ReputationTier = 'Novice' THEN upp.UserId END) as NoviceUsers,
    COUNT(DISTINCT CASE WHEN upp.ReputationTier = 'Beginner' THEN upp.UserId END) as BeginnerUsers,
    AVG(upp.Reputation) as AvgReputation,
    AVG(upp.PostCount) as AvgPostCount,
    AVG(upp.QuestionCount) as AvgQuestionCount,
    AVG(upp.AnswerCount) as AvgAnswerCount,
    AVG(upp.BadgeCount) as AvgBadgeCount,
    AVG(upp.TotalScore) as AvgTotalScore,
    AVG(upp.AvgScore) as AvgAvgScore,
    COUNT(DISTINCT upp.PostId) as TotalPosts,
    COUNT(DISTINCT CASE WHEN upp.ScoringTier = 'Top 100' THEN upp.PostId END) as Top100Posts,
    COUNT(DISTINCT CASE WHEN upp.ScoringTier = 'Top 500' THEN upp.PostId END) as Top500Posts,
    COUNT(DISTINCT CASE WHEN upp.ScoringTier = 'Top 1000' THEN upp.PostId END) as Top1000Posts,
    AVG(upp.PostScore) as AvgPostScore,
    AVG(upp.PostScore) filter (WHERE ep1.ScoreRank <= 100) as Top100AvgScore,
    AVG(upp.PostScore) filter (WHERE ep1.ScoreRank <= 500) as Top500AvgScore,
    AVG(upp.PostScore) filter (WHERE ep1.ScoreRank <= 1000) as Top1000AvgScore,
    AVG(upp.ScoreToViewRatio) as AvgScoreToViewRatio,
    AVG(upp.ScorePerAnswer) as AvgScorePerAnswer,
    AVG(upp.ScorePerComment) as AvgScorePerComment,
    COUNT(DISTINCT CASE WHEN upp.PopularityCategory = 'Popular' THEN upp.PostId END) as PopularPosts,
    COUNT(DISTINCT CASE WHEN upp.PopularityCategory = 'Moderate' THEN upp.PostId END) as ModeratePosts,
    COUNT(DISTINCT CASE WHEN upp.PopularityCategory = 'Low' THEN upp.PostId END) as LowPosts,
    MAX(upp.Reputation) as MaxReputation,
    MIN(upp.Reputation) as MinReputation,
    SUM(upp.PostCount) as TotalPostCount,
    SUM(upp.QuestionCount) as TotalQuestionCount,
    SUM(upp.AnswerCount) as TotalAnswerCount,
    SUM(upp.BadgeCount) as TotalBadgeCount,
    SUM(upp.TotalScore) as TotalScoreAchieved,
    SUM(upp.PostScore) as TotalPostScore,
    COALESCE(
        (
            SELECT COUNT(*) 
            FROM PostHistory ph 
            INNER JOIN Posts p ON ph.PostId = p.Id 
            WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30)
            AND ph.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '30 days'
        ), 0
    ) as RecentActivityCount,
    COALESCE(
        (
            SELECT STRING_AGG(DISTINCT ph.Comment, ', ')
            FROM PostHistory ph 
            WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30)
            AND ph.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '30 days'
            LIMIT 10
        ), 'No Recent Activity'
    ) as RecentActivitySummary,
    COUNT(DISTINCT CASE WHEN upp.UpVoteCount > 0 THEN upp.PostId END) as PostsWithUpVotes,
    COUNT(DISTINCT CASE WHEN upp.DownVoteCount > 0 THEN upp.PostId END) as PostsWithDownVotes,
    COUNT(DISTINCT CASE WHEN upp.ViewRank <= 100 THEN upp.PostId END) as HighViewPosts,
    COUNT(DISTINCT CASE WHEN upp.NewnessRank <= 100 THEN upp.PostId END) as NewPosts,
    AVG(upp.ScoreToViewRatio) filter (WHERE upp.PostScore > 10 AND upp.PostViewCount > 100) as PopularScoreViewRatio,
    COUNT(DISTINCT CASE 
        WHEN upp.ScorePerAnswer > 10 AND upp.PostAnswerCount > 1 THEN upp.PostId 
        ELSE NULL 
    END) as HighScorePerAnswerPosts,
    COUNT(DISTINCT CASE 
        WHEN upp.ScorePerComment > 5 AND upp.PostCommentCount > 1 THEN upp.PostId 
        ELSE NULL 
    END) as HighScorePerCommentPosts,
    COUNT(DISTINCT CASE 
        WHEN upp.ReputationRank <= 100 THEN upp.UserId 
        ELSE NULL 
    END) as HighReputationUsers,
    COUNT(DISTINCT CASE 
        WHEN upp.ViewRank <= 1000 THEN upp.UserId 
        ELSE NULL 
    END) as HighViewUsers
FROM UserPostPerformance upp
LEFT JOIN EngagementAnalysis ep1 ON upp.PostId = ep1.PostId
WHERE upp.UserId IS NOT NULL
GROUP BY 
    upp.UserId,
    upp.Reputation,
    upp.PostCount,
    upp.QuestionCount,
    upp.AnswerCount,
    upp.BadgeCount,
    upp.TotalScore,
    upp.AvgScore,
    upp.ReputationRank,
    upp.ViewRank,
    upp.ReputationTier,
    ep1.PostId,
    ep1.OwnerUserId,
    ep1.Score,
    ep1.ViewCount,
    ep1.AnswerCount,
    ep1.CommentCount,
    ep1.CreationDate,
    ep1.Title,
    ep1.Tags,
    ep1.ParentId,
    ep1.ScoreToViewRatio,
    ep1.ScorePerAnswer,
    ep1.ScorePerComment,
    ep1.ScoreRank,
    ep1.ViewRank,
    ep1.NewnessRank,
    ep1.PostScore,
    ep1.PostViewCount,
    ep1.PostAnswerCount,
    ep1.PostCommentCount,
    upp.ScoringTier,
    upp.UpVoteCount,
    upp.DownVoteCount,
    upp.PopularityCategory
HAVING 
    COUNT(*) > 0
ORDER BY 
    AVG(upp.Reputation) DESC
LIMIT 1000;