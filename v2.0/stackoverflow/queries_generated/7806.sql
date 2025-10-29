-- {"query": "7806.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2274} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        DATEDIFF('day', u.CreationDate, CURRENT_TIMESTAMP) as AccountAgeDays,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Elite'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Regular'
            ELSE 'Newbie'
        END as UserRank,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        PERCENT_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationPercentile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.CreationDate
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
        p.LastActivityDate,
        p.Tags,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                (CASE WHEN p.AnswerCount > 0 THEN 1 ELSE 0 END) * 
                (CASE WHEN p.CommentCount > 10 THEN 1 ELSE 0 END) * 
                (CASE WHEN p.Score > 50 THEN 1 ELSE 0 END)
            WHEN p.PostTypeId = 2 THEN 
                (CASE WHEN p.Score > 10 THEN 1 ELSE 0 END) * 
                (CASE WHEN p.CommentCount > 5 THEN 1 ELSE 0 END)
            ELSE 0
        END as ComplexityScore,
        COALESCE(LENGTH(p.Body), 0) as BodyLength,
        COALESCE(LENGTH(p.Title), 0) as TitleLength,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0 THEN 
                (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1)
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.PostTypeId = 1 THEN 'Unanswered'
            ELSE 'Other'
        END as PostStatus,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as AgeInDays,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PostSequence
    FROM Posts p
),
UserPostTrends AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.TotalScore,
        uas.TotalViews,
        uas.UserRank,
        uas.PostRank,
        uas.ReputationPercentile,
        AVG(pcs.Score) as AvgPostScore,
        AVG(pcs.ViewCount) as AvgPostViews,
        MAX(pcs.ComplexityScore) as MaxComplexity,
        SUM(CASE WHEN pcs.PostStatus = 'Answered' THEN 1 ELSE 0 END) as AnsweredQuestions,
        SUM(CASE WHEN pcs.PostStatus = 'Closed' THEN 1 ELSE 0 END) as ClosedPosts,
        SUM(CASE WHEN pcs.BodyLength > 1000 THEN 1 ELSE 0 END) as LongPosts,
        COUNT(CASE WHEN pcs.AgeInDays <= 30 THEN 1 END) as RecentPosts,
        COUNT(CASE WHEN pcs.TagCount > 3 THEN 1 END) as MultiTagPosts,
        SUM(CASE WHEN pcs.Score > 0 THEN pcs.Score ELSE 0 END) as PositiveScorePosts,
        SUM(CASE WHEN pcs.Score < 0 THEN ABS(pcs.Score) ELSE 0 END) as NegativeScorePosts,
        AVG(pcs.BodyLength) as AvgBodyLength,
        AVG(pcs.TitleLength) as AvgTitleLength
    FROM UserActivityStats uas
    LEFT JOIN PostComplexity pcs ON uas.UserId = pcs.OwnerUserId
    GROUP BY uas.UserId, uas.DisplayName, uas.Reputation, uas.TotalPosts, uas.Questions, uas.Answers, 
             uas.Comments, uas.Badges, uas.TotalScore, uas.TotalViews, uas.UserRank, uas.PostRank, uas.ReputationPercentile
),
TopUsers AS (
    SELECT 
        *,
        NTILE(10) OVER (ORDER BY TotalScore DESC) as ScoreDecile,
        NTILE(5) OVER (ORDER BY Reputation DESC) as ReputationQuintile,
        DENSE_RANK() OVER (ORDER BY TotalPosts DESC) as PostsRank
    FROM UserPostTrends
),
ComplexUserAnalysis AS (
    SELECT 
        tu.*,
        CASE 
            WHEN tu.Reputation >= 100000 THEN 'Legend'
            WHEN tu.Reputation >= 50000 THEN 'Master'
            WHEN tu.Reputation >= 10000 THEN 'Expert'
            WHEN tu.Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ExpertiseLevel,
        CASE 
            WHEN tu.TotalPosts >= 500 THEN 'Veteran Poster'
            WHEN tu.TotalPosts >= 100 THEN 'Experienced Poster'
            WHEN tu.TotalPosts >= 10 THEN 'Regular Poster'
            ELSE 'Occasional Poster'
        END as PostingFrequency,
        CASE 
            WHEN tu.Questions > 0 AND tu.Answers > 0 THEN 'Both Questioner and Answerer'
            WHEN tu.Questions > 0 THEN 'Questioner Only'
            WHEN tu.Answers > 0 THEN 'Answerer Only'
            ELSE 'Neither'
        END as RoleMix,
        CAST(tu.Reputation AS FLOAT) / NULLIF(CAST(tu.TotalPosts AS FLOAT), 0) as ReputationPerPost,
        CAST(tu.PositiveScorePosts AS FLOAT) / NULLIF(CAST(tu.TotalPosts AS FLOAT), 0) as PositivityRatio,
        (tu.Comments * 100.0) / NULLIF(tu.TotalPosts, 0) as CommentsPerPost,
        ROUND((tu.AvgPostViews * 100.0) / NULLIF(tu.AvgPostScore, 0), 2) as ViewsPerScore,
        CASE 
            WHEN ABS(tu.AvgPostScore - tu.PrevScore) > 10 THEN 'Highly Active'
            WHEN ABS(tu.AvgPostScore - tu.PrevScore) > 5 THEN 'Moderately Active'
            ELSE 'Stable'
        END as ActivityPattern
    FROM TopUsers tu
)
SELECT 
    cua.UserId,
    cua.DisplayName,
    cua.Reputation,
    cua.TotalPosts,
    cua.Questions,
    cua.Answers,
    cua.Comments,
    cua.Badges,
    cua.TotalScore,
    cua.TotalViews,
    cua.UserRank,
    cua.PostRank,
    cua.ReputationPercentile,
    cua.AvgPostScore,
    cua.AvgPostViews,
    cua.MaxComplexity,
    cua.AnsweredQuestions,
    cua.ClosedPosts,
    cua.LongPosts,
    cua.RecentPosts,
    cua.MultiTagPosts,
    cua.PositiveScorePosts,
    cua.NegativeScorePosts,
    cua.AvgBodyLength,
    cua.AvgTitleLength,
    cua.ExpertiseLevel,
    cua.PostingFrequency,
    cua.RoleMix,
    cua.ReputationPerPost,
    cua.PositivityRatio,
    cua.CommentsPerPost,
    cua.ViewsPerScore,
    cua.ActivityPattern,
    cua.ScoreDecile,
    cua.ReputationQuintile,
    cua.PostsRank,
    CONCAT(
        'User: ', cua.DisplayName, 
        ' | Rep: ', cua.Reputation, 
        ' | Posts: ', cua.TotalPosts,
        ' | Score: ', cua.TotalScore,
        ' | Views: ', cua.TotalViews,
        ' | Rank: ', cua.UserRank,
        ' | Expertise: ', cua.ExpertiseLevel,
        ' | Activity: ', cua.ActivityPattern
    ) as UserSummary,
    CASE 
        WHEN cua.Reputation > 10000 AND cua.TotalPosts > 100 AND cua.PositiveScorePosts > 50 THEN 'High Achiever'
        WHEN cua.Reputation > 5000 AND cua.TotalPosts > 50 THEN 'Good Contributor'
        WHEN cua.Reputation > 1000 AND cua.TotalPosts > 20 THEN 'Active Member'
        ELSE 'Casual Participant'
    END as ContributionLevel,
    RANK() OVER (ORDER BY cua.TotalScore DESC, cua.Reputation DESC) as OverallRank
FROM ComplexUserAnalysis cua
WHERE cua.TotalPosts > 5 
    AND cua.Reputation > 100
    AND (cua.Questions > 0 OR cua.Answers > 0)
    AND cua.ReputationPercentile > 0.05
ORDER BY cua.TotalScore DESC, cua.Reputation DESC
LIMIT 1000;