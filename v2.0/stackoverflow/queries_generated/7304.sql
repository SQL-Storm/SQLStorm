-- {"query": "7304.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2507} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT b.Id) AS Badges,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate) AS AccountAgeDays,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Veteran'
            WHEN u.Reputation >= 100 THEN 'Regular'
            ELSE 'Newbie'
        END AS ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS Rank
    FROM Tags t
    WHERE t.Count > 1000
),
PostPerformance AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Upvoted'
            WHEN p.Score > 50 THEN 'Upvoted'
            WHEN p.Score > 0 THEN 'Neutral'
            WHEN p.Score < 0 THEN 'Downvoted'
            ELSE 'No Votes'
        END AS EngagementLevel,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) AS AgeInDays,
        p.Tags,
        STRING_AGG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END, ',') AS UpvoteIndicators,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        COUNT(DISTINCT v.Id) AS TotalVotes
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 YEAR)
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.CreationDate, p.OwnerUserId, u.DisplayName, p.PostTypeId, p.Tags
),
UserEngagement AS (
    SELECT 
        up.UserId,
        up.DisplayName,
        up.Reputation,
        up.TotalPosts,
        up.Questions,
        up.Answers,
        up.Badges,
        up.AvgScore,
        up.LastPostDate,
        up.AccountAgeDays,
        up.ReputationTier,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        COALESCE(MIN(p.CreationDate), CURRENT_TIMESTAMP) AS FirstPostDate,
        COALESCE(MAX(p.CreationDate), CURRENT_TIMESTAMP) AS LastPostDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS WikiCount,
        SUM(CASE WHEN p.ViewCount IS NOT NULL THEN p.ViewCount ELSE 0 END) AS TotalViews,
        AVG(CASE WHEN p.AnswerCount IS NOT NULL THEN p.AnswerCount ELSE 0 END) AS AvgAnswers,
        COUNT(DISTINCT p.Id) AS ActivePosts,
        STRING_AGG(DISTINCT p.Title, ', ') AS PostTitles,
        STRING_AGG(DISTINCT p.Tags, ', ') AS PostTags,
        STRING_AGG(CASE WHEN v.VoteTypeId = 2 THEN 'Up' ELSE 'Down' END, ', ') AS VoteHistory,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM UserStats up
    LEFT JOIN Posts p ON up.UserId = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY 
        up.UserId, up.DisplayName, up.Reputation, up.TotalPosts, up.Questions, up.Answers,
        up.Badges, up.AvgScore, up.LastPostDate, up.AccountAgeDays, up.ReputationTier
)
SELECT 
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.Questions,
    ue.Answers,
    ue.Badges,
    ue.AvgScore,
    ue.LastPostDate,
    ue.AccountAgeDays,
    ue.ReputationTier,
    ue.TotalScore,
    ue.AvgPostScore,
    ue.FirstPostDate,
    ue.LastPostDate,
    ue.QuestionCount,
    ue.AnswerCount,
    ue.WikiCount,
    ue.TotalViews,
    ue.AvgAnswers,
    ue.ActivePosts,
    CASE 
        WHEN (ue.TotalScore > 1000 AND ue.AvgPostScore > 10) THEN 'Highly Engaged'
        WHEN (ue.TotalScore > 500 AND ue.AvgPostScore > 5) THEN 'Engaged'
        WHEN (ue.TotalScore > 100 AND ue.AvgPostScore > 1) THEN 'Moderately Engaged'
        ELSE 'Low Engagement'
    END AS EngagementLevel,
    COALESCE(ue.PostTitles, 'No Titles') AS PostTitles,
    COALESCE(ue.PostTags, 'No Tags') AS PostTags,
    COALESCE(ue.VoteHistory, 'No Votes') AS VoteHistory,
    ue.TotalVotes,
    ue.UpvoteCount,
    ue.DownvoteCount,
    ue.CommentCount,
    (ue.TotalVotes * 100.0 / NULLIF(ue.ActivePosts, 0)) AS AvgVotesPerPost,
    (ue.UpvoteCount * 100.0 / NULLIF(ue.TotalVotes, 0)) AS UpvotePercentage,
    (ue.DownvoteCount * 100.0 / NULLIF(ue.TotalVotes, 0)) AS DownvotePercentage,
    CASE 
        WHEN (ue.UpvoteCount * 1.0 / NULLIF(ue.DownvoteCount, 0)) > 2 THEN 'Positively Bias'
        WHEN (ue.UpvoteCount * 1.0 / NULLIF(ue.DownvoteCount, 0)) < 0.5 THEN 'Negatively Bias'
        ELSE 'Balanced'
    END AS VotingBias,
    CASE 
        WHEN ue.ActivePosts > 50 THEN 'High Activity'
        WHEN ue.ActivePosts > 20 THEN 'Medium Activity'
        WHEN ue.ActivePosts > 5 THEN 'Low Activity'
        ELSE 'Minimal Activity'
    END AS ActivityLevel,
    CONCAT('User-', ue.UserId, '-Rep-', CAST(ue.Reputation AS VARCHAR(10))) AS UserIdentifier,
    CASE 
        WHEN (ue.ReputationTier = 'Elite' AND ue.TotalPosts >= 100) THEN 'Elite Contributor'
        WHEN (ue.ReputationTier = 'Veteran' AND ue.TotalPosts >= 50) THEN 'Veteran Contributor'
        WHEN (ue.ReputationTier = 'Regular' AND ue.TotalPosts >= 25) THEN 'Regular Contributor'
        ELSE 'Contributor'
    END AS ContributionStatus,
    CASE 
        WHEN ue.Reputation > 50000 THEN 'Legendary'
        WHEN ue.Reputation > 10000 THEN 'Expert'
        WHEN ue.Reputation > 1000 THEN 'Advanced'
        ELSE 'Beginner'
    END AS ExpertiseLevel,
    DATEDIFF(CURRENT_TIMESTAMP, ue.FirstPostDate) AS DaysSinceFirstPost,
    DATEDIFF(CURRENT_TIMESTAMP, ue.LastPostDate) AS DaysSinceLastPost,
    CASE 
        WHEN (DATEDIFF(CURRENT_TIMESTAMP, ue.LastPostDate) <= 30) THEN 'Recently Active'
        WHEN (DATEDIFF(CURRENT_TIMESTAMP, ue.LastPostDate) <= 90) THEN 'Occasionally Active'
        ELSE 'Inactive'
    END AS ActivityStatus,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS PostCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    NULLIF(ue.TotalPosts - (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)), 0) AS AnswerPercentage,
    CASE 
        WHEN ue.Badges > 50 THEN 'Awarded'
        WHEN ue.Badges > 20 THEN 'Recognized'
        WHEN ue.Badges > 5 THEN 'Notable'
        ELSE 'Regular'
    END AS BadgeStatus,
    (ue.TotalViews * 1.0 / NULLIF(ue.ActivePosts, 0)) AS AvgViewsPerPost,
    (ue.TotalScore * 1.0 / NULLIF(ue.TotalPosts, 0)) AS AvgScorePerPost,
    CASE 
        WHEN ue.Questions > 0 AND ue.Answers > 0 THEN 
            CAST((ue.Answers * 100.0 / NULLIF(ue.Questions, 0)) AS DECIMAL(5,2))
        ELSE 0
    END AS AnswerToQuestionRatio,
    COALESCE((ue.UpvoteCount - ue.DownvoteCount) * 100.0 / NULLIF(ue.TotalVotes, 0), 0) AS NetVotePercentage,
    DATEDIFF(CURRENT_TIMESTAMP, MAX(ue.ActivePosts)) AS RecentActivityDays
FROM UserEngagement ue
LEFT JOIN Posts p ON ue.UserId = p.OwnerUserId
GROUP BY 
    ue.UserId, ue.DisplayName, ue.Reputation, ue.TotalPosts, ue.Questions, ue.Answers,
    ue.Badges, ue.AvgScore, ue.LastPostDate, ue.AccountAgeDays, ue.ReputationTier,
    ue.TotalScore, ue.AvgPostScore, ue.FirstPostDate, ue.LastPostDate,
    ue.QuestionCount, ue.AnswerCount, ue.WikiCount, ue.TotalViews, ue.AvgAnswers,
    ue.ActivePosts, ue.PostTitles, ue.PostTags, ue.VoteHistory, ue.TotalVotes,
    ue.UpvoteCount, ue.DownvoteCount, ue.CommentCount
HAVING 
    ue.ActivePosts >= 1
ORDER BY 
    ue.TotalScore DESC,
    ue.Reputation DESC,
    ue.TotalPosts DESC,
    ue.LastPostDate DESC
LIMIT 25;