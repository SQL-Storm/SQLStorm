-- {"query": "7439.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2124} 
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
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as RepRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopQuestionTags AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as TopUsers,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as TagRank
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2015-01-01'
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) > 100
),
PostDetailAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.Tags, '') as Tags,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            WHEN p.Score = 0 THEN 'NoVotes'
            ELSE 'Negative'
        END as VoteCategory,
        DATEDIFF(day, p.CreationDate, COALESCE(p.LastEditDate, p.LastActivityDate)) as DaysActive,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            ELSE 'Active'
        END as PostStatus,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        COALESCE(LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), 0) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as UserRank,
        NTILE(10) OVER (ORDER BY p.Score DESC) as ScoreDecile
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= '2018-01-01' 
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
)
SELECT 
    'PostPerformanceAnalysis' as AnalysisType,
    COUNT(*) as TotalPosts,
    COUNT(CASE WHEN pa.PostStatus = 'Active' THEN 1 END) as ActivePosts,
    COUNT(CASE WHEN pa.PostStatus = 'Closed' THEN 1 END) as ClosedPosts,
    COUNT(CASE WHEN pa.PostStatus = 'CommunityOwned' THEN 1 END) as CommunityOwnedPosts,
    AVG(pa.Score) as AvgScore,
    MAX(pa.Score) as MaxScore,
    MIN(pa.Score) as MinScore,
    STDDEV(pa.Score) as ScoreStdDev,
    AVG(pa.ViewCount) as AvgViews,
    AVG(pa.AnswerCount) as AvgAnswers,
    AVG(pa.CommentCount) as AvgComments,
    STRING_AGG(DISTINCT CASE WHEN t.TagRank <= 5 THEN t.TagName END, ', ') as TopTags,
    STRING_AGG(DISTINCT CASE WHEN u.ScoreRank <= 10 THEN u.DisplayName END, ', ') as TopUsers,
    COUNT(DISTINCT CASE WHEN pa.VoteCategory = 'HighlyVoted' THEN pa.PostId END) as HighlyVoted,
    COUNT(DISTINCT CASE WHEN pa.VoteCategory = 'ModeratelyVoted' THEN pa.PostId END) as ModeratelyVoted,
    COUNT(DISTINCT CASE WHEN pa.VoteCategory = 'LowVoted' THEN pa.PostId END) as LowVoted,
    COUNT(DISTINCT CASE WHEN pa.VoteCategory = 'NoVotes' THEN pa.PostId END) as NoVotes,
    COUNT(DISTINCT CASE WHEN pa.VoteCategory = 'Negative' THEN pa.PostId END) as NegativeVotes,
    COUNT(DISTINCT CASE WHEN pa.Score > 0 THEN pa.OwnerUserId END) as UsersWithPositiveScore,
    COUNT(DISTINCT CASE WHEN pa.Score < 0 THEN pa.OwnerUserId END) as UsersWithNegativeScore,
    COUNT(DISTINCT CASE WHEN pa.Score = 0 THEN pa.OwnerUserId END) as UsersWithZeroScore,
    COUNT(DISTINCT CASE WHEN pa.Score IS NULL THEN pa.OwnerUserId END) as UsersWithNullScore,
    CASE WHEN COUNT(pa.OwnerUserId) > 0 THEN 
        ROUND(100.0 * COUNT(CASE WHEN pa.Score > 0 THEN 1 END) / COUNT(pa.OwnerUserId), 2) 
    END as PercentagePositiveScore,
    CASE WHEN COUNT(pa.OwnerUserId) > 0 THEN 
        ROUND(100.0 * COUNT(CASE WHEN pa.Score < 0 THEN 1 END) / COUNT(pa.OwnerUserId), 2) 
    END as PercentageNegativeScore,
    CASE WHEN COUNT(pa.OwnerUserId) > 0 THEN 
        ROUND(100.0 * COUNT(CASE WHEN pa.Score = 0 THEN 1 END) / COUNT(pa.OwnerUserId), 2) 
    END as PercentageZeroScore
FROM PostDetailAnalysis pa
LEFT JOIN TopQuestionTags t ON pa.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN UserActivityStats u ON pa.OwnerUserId = u.UserId
WHERE pa.CreationDate >= '2018-01-01'
GROUP BY 
    CASE WHEN COUNT(pa.OwnerUserId) > 0 THEN 1 END,
    CASE WHEN COUNT(pa.OwnerUserId) > 0 THEN 1 END,
    CASE WHEN COUNT(pa.OwnerUserId) > 0 THEN 1 END,
    CASE WHEN COUNT(pa.OwnerUserId) > 0 THEN 1 END
HAVING COUNT(pa.OwnerUserId) > 0
UNION ALL
SELECT 
    'UserActivitySummary' as AnalysisType,
    COUNT(*) as TotalPosts,
    COUNT(CASE WHEN u.RepRank <= 10 THEN 1 END) as TopReputationUsers,
    COUNT(CASE WHEN u.RepRank > 10 AND u.RepRank <= 100 THEN 1 END) as MidReputationUsers,
    COUNT(CASE WHEN u.RepRank > 100 THEN 1 END) as LowReputationUsers,
    AVG(u.Reputation) as AvgReputation,
    MAX(u.Reputation) as MaxReputation,
    MIN(u.Reputation) as MinReputation,
    STDDEV(u.Reputation) as RepStdDev,
    AVG(u.TotalPosts) as AvgPosts,
    AVG(u.Questions) as AvgQuestions,
    AVG(u.Answers) as AvgAnswers,
    AVG(u.Comments) as AvgComments,
    AVG(u.Badges) as AvgBadges,
    STRING_AGG(DISTINCT u.DisplayName, ', ') as AllUserNames,
    COUNT(DISTINCT CASE WHEN u.TotalPosts > 100 THEN u.UserId END) as HighActivityUsers,
    COUNT(DISTINCT CASE WHEN u.TotalPosts BETWEEN 50 AND 100 THEN u.UserId END) as MediumActivityUsers,
    COUNT(DISTINCT CASE WHEN u.TotalPosts < 50 THEN u.UserId END) as LowActivityUsers,
    ROUND(100.0 * AVG(u.TotalPosts) / AVG(COUNT(p.Id)) OVER(), 2) as ActivityPercentage,
    COUNT(CASE WHEN u.ScoreRank <= 5 THEN 1 END) as TopScoreUsers,
    COUNT(CASE WHEN u.ScoreRank > 5 AND u.ScoreRank <= 20 THEN 1 END) as MidScoreUsers,
    COUNT(CASE WHEN u.ScoreRank > 20 THEN 1 END) as LowScoreUsers,
    'N/A' as PercentagePositiveScore,
    'N/A' as PercentageNegativeScore,
    'N/A' as PercentageZeroScore
FROM UserActivityStats u
LEFT JOIN Posts p ON u.UserId = p.OwnerUserId
WHERE u.CreationDate >= '2010-01-01'
GROUP BY 
    CASE WHEN COUNT(u.UserId) > 0 THEN 1 END,
    CASE WHEN COUNT(u.UserId) > 0 THEN 1 END,
    CASE WHEN COUNT(u.UserId) > 0 THEN 1 END,
    CASE WHEN COUNT(u.UserId) > 0 THEN 1 END
HAVING COUNT(u.UserId) > 0
ORDER BY 1 DESC;