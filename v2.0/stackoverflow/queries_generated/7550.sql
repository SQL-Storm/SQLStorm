-- {"query": "7550.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1728} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN AVG(p.Score) 
            ELSE 0 
        END as AvgPostScore,
        CASE 
            WHEN COUNT(DISTINCT c.Id) > 0 THEN AVG(c.Score) 
            ELSE 0 
        END as AvgCommentScore,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= '2010-01-01' 
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByRep,
        DENSE_RANK() OVER (ORDER BY AvgPostScore DESC) as RankByAvgScore,
        NTILE(10) OVER (ORDER BY Reputation) as ReputationDecile
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
        p.Tags,
        p.PostTypeId,
        CASE 
            WHEN p.Score > 0 THEN 'Positive'
            WHEN p.Score < 0 THEN 'Negative'
            ELSE 'Neutral'
        END as ScoreCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'HighViews'
            WHEN p.ViewCount > 100 THEN 'MediumViews'
            ELSE 'LowViews'
        END as ViewCategory,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) as CommentCount,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2), 0) as UpVotes,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3), 0) as DownVotes,
        COALESCE((SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10), 0) as ClosedCount,
        COALESCE((SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 12), 0) as DeletedCount,
        COALESCE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '') as CleanTags,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1)
            ELSE 0
        END as TagCount,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.PostTypeId = 1 THEN 'Unanswered'
            ELSE 'Other'
        END as QuestionStatus
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
),
UserPerformance AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.PostCount,
        ru.CommentCount,
        ru.BadgeCount,
        ru.VoteCount,
        ru.AvgPostScore,
        ru.AvgCommentScore,
        ru.LastPostDate,
        ru.LastCommentDate,
        CASE 
            WHEN ru.PostCount > 1000 THEN 'Elite'
            WHEN ru.PostCount > 100 THEN 'Experienced'
            WHEN ru.PostCount > 10 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ExperienceLevel,
        CASE 
            WHEN ru.BadgeCount > 50 THEN 'BadgeMaster'
            WHEN ru.BadgeCount > 25 THEN 'BadgeEnthusiast'
            WHEN ru.BadgeCount > 10 THEN 'BadgeFollower'
            ELSE 'BadgeStranger'
        END as BadgeTier,
        DATEDIFF('day', ru.CreationDate, ru.LastPostDate) as DaysActive,
        CASE 
            WHEN ru.PostCount > 0 THEN (ru.VoteCount * 100.0 / ru.PostCount)
            ELSE 0
        END as VoteToPostRatio
    FROM RankedUsers ru
    WHERE ru.RankByRep <= 1000
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.IsRequired,
        t.IsModeratorOnly,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'ModeratelyPopular'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as PopularityCategory,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as PostCountWithTag,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as AvgScoreForTag
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
)
SELECT 
    'Performance Results' as ReportName,
    COUNT(*) as TotalUsers,
    COUNT(DISTINCT pa.OwnerUserId) as UsersWithPosts,
    AVG(up.VoteToPostRatio) as AvgVoteToPostRatio,
    AVG(pa.Score) as AvgPostScore,
    AVG(pa.ViewCount) as AvgViewCount,
    AVG(ta.AvgScoreForTag) as AvgTagScore,
    MIN(up.DaysActive) as MinDaysActive,
    MAX(up.DaysActive) as MaxDaysActive,
    COUNT(CASE WHEN pa.QuestionStatus = 'Answered' THEN 1 END) as AnsweredQuestions,
    COUNT(CASE WHEN pa.QuestionStatus = 'Unanswered' THEN 1 END) as UnansweredQuestions,
    COUNT(CASE WHEN pa.QuestionStatus = 'Other' THEN 1 END) as OtherPostTypes,
    COUNT(CASE WHEN pa.ScoreCategory = 'Positive' THEN 1 END) as PositiveScorePosts,
    COUNT(CASE WHEN pa.ScoreCategory = 'Negative' THEN 1 END) as NegativeScorePosts,
    COUNT(CASE WHEN pa.ViewCategory = 'HighViews' THEN 1 END) as HighViewPosts,
    COUNT(CASE WHEN pa.ViewCategory = 'MediumViews' THEN 1 END) as MediumViewPosts,
    COUNT(CASE WHEN pa.ViewCategory = 'LowViews' THEN 1 END) as LowViewPosts,
    COUNT(DISTINCT SUBSTRING(pa.Tags, 2, LENGTH(pa.Tags)-2)) as UniqueTags,
    COUNT(DISTINCT ta.TagName) as TotalTags,
    CASE 
        WHEN COUNT(*) > 0 THEN (COUNT(CASE WHEN up.ExperienceLevel = 'Elite' THEN 1 END) * 100.0 / COUNT(*))
        ELSE 0 
    END as ElitePercentage,
    CASE 
        WHEN COUNT(*) > 0 THEN (COUNT(CASE WHEN up.BadgeTier = 'BadgeMaster' THEN 1 END) * 100.0 / COUNT(*))
        ELSE 0 
    END as BadgeMasterPercentage,
    NOW() as ReportGeneratedAt
FROM UserPerformance up
LEFT JOIN PostAnalysis pa ON up.UserId = pa.OwnerUserId
LEFT JOIN TagAnalysis ta ON TRUE
WHERE up.UserId IS NOT NULL
HAVING COUNT(*) > 0
ORDER BY up.Reputation DESC
LIMIT 1000;