-- {"query": "7145.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1951} 
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) as TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) FILTER (WHERE p.Tags IS NOT NULL), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as RankByPopularity,
        AVG(t.Count) OVER () as AvgTagCount
    FROM Tags t
    WHERE t.Count > 100
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        COUNT(v.Id) as TotalVotes,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) as Favorites,
        COALESCE(AVG(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8), 0) as AvgBountyAmount
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'WellVoted'
            WHEN p.Score > 10 THEN 'ModeratelyVoted'
            ELSE 'LowVoted'
        END as ScoreCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'ModeratelyPopular'
            ELSE 'LessPopular'
        END as PopularityCategory,
        CASE 
            WHEN p.CommentCount > 10 THEN 'HighlyDiscussed'
            WHEN p.CommentCount > 5 THEN 'ModeratelyDiscussed'
            ELSE 'LessDiscussed'
        END as DiscussionCategory,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        p.CreationDate::DATE as PostDate,
        EXTRACT(YEAR FROM p.CreationDate) as PostYear,
        EXTRACT(MONTH FROM p.CreationDate) as PostMonth
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
RecentActivity AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CommentCount,
        pa.OwnerUserId,
        pa.ScoreCategory,
        pa.PopularityCategory,
        pa.DiscussionCategory,
        pa.PostYear,
        pa.PostMonth,
        ROW_NUMBER() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate DESC) as RecentActivityRank
    FROM PostAnalysis pa
    WHERE pa.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
TagUsageAnalysis AS (
    SELECT 
        ta.PostId,
        ta.Title,
        STRING_TO_ARRAY(SUBSTRING(ta.Tags, 2, LENGTH(ta.Tags) - 2), '><') as TagArray,
        ta.Tags,
        CASE 
            WHEN ta.PostTypeId = 1 THEN 'Question'
            ELSE 'Answer'
        END as PostType,
        ta.Score,
        ta.ViewCount,
        ta.CommentCount
    FROM PostAnalysis ta
    WHERE ta.Tags IS NOT NULL AND ta.Tags != ''
),
AggregateTagStats AS (
    SELECT 
        t.TagName,
        t.Count,
        t.Count * 1.0 / (SELECT SUM(Count) FROM Tags) as PercentageOfAllTags,
        STRING_AGG(DISTINCT CASE 
            WHEN pa.PostTypeId = 1 THEN 'Question' 
            ELSE 'Answer' 
        END, ', ') as PostTypes,
        AVG(pa.Score) as AvgScore,
        MAX(pa.ViewCount) as MaxViews
    FROM Tags t
    JOIN TagUsageAnalysis tta ON t.TagName = ANY(tta.TagArray)
    JOIN PostAnalysis pa ON pa.PostId = tta.PostId
    WHERE t.Count > 50
    GROUP BY t.TagName, t.Count
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(DISTINCT ups.UserId) as TotalUsers,
    COUNT(DISTINCT pa.PostId) as TotalPosts,
    COUNT(DISTINCT ta.PostId) as TaggedPosts,
    (SELECT COUNT(*) FROM Tags WHERE Count > 50) as PopularTags,
    SUM(ups.TotalScore) as TotalCommunityScore,
    AVG(ups.Reputation) as AverageReputation,
    MAX(ups.LastPostDate) as MostRecentPost,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13)) as RecentModifications,
    COUNT(DISTINCT CASE 
        WHEN ups.QuestionCount > 10 AND ups.AnswerCount > 5 THEN ups.UserId 
        ELSE NULL 
    END) as ActiveContributors,
    MAX(CASE 
        WHEN ats.PercentageOfAllTags > 0.05 THEN ats.TagName 
        ELSE NULL 
    END) as DominantTag,
    STRING_AGG(DISTINCT CASE 
        WHEN ups.Reputation > 10000 THEN ups.DisplayName 
        ELSE NULL 
    END, ', ') as HighReputationUsers,
    COUNT(DISTINCT CASE 
        WHEN ra.RecentActivityRank = 1 THEN ra.PostId 
        ELSE NULL 
    END) as RecentPosts,
    (SELECT COUNT(DISTINCT p.Id) FROM Posts p WHERE p.Score > 1000 AND p.PostTypeId = 1) as HighScoringQuestions,
    (SELECT AVG(pa.Score) FROM PostAnalysis pa WHERE pa.PostTypeId = 1) as AvgQuestionScore,
    (SELECT AVG(pa.Score) FROM PostAnalysis pa WHERE pa.PostTypeId = 2) as AvgAnswerScore,
    COUNT(DISTINCT v.Id) as TotalVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as Downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as Favorites,
    STRING_AGG(DISTINCT CASE 
        WHEN ta.PostType = 'Question' THEN ta.Title 
        ELSE NULL 
    END, ' | ') FILTER (WHERE ta.PostType = 'Question') as SampleQuestions,
    STRING_AGG(DISTINCT CASE 
        WHEN ta.PostType = 'Answer' THEN ta.Title 
        ELSE NULL 
    END, ' | ') FILTER (WHERE ta.PostType = 'Answer') as SampleAnswers,
    COUNT(DISTINCT ph.Id) as HistoryEntries,
    COUNT(DISTINCT CASE 
        WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN ph.PostId 
        ELSE NULL 
    END) as ModifedPosts,
    COUNT(DISTINCT c.Id) as CommentsCount,
    AVG(ups.TotalPosts) as AvgPostsPerUser,
    MAX(ups.QuestionCount) as MaxQuestionsByUser,
    MAX(ups.AnswerCount) as MaxAnswersByUser,
    STRING_AGG(DISTINCT pht.Name, ', ') as PostHistoryTypes,
    COUNT(DISTINCT b.Id) as TotalBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges
FROM UserPostStats ups
LEFT JOIN PostAnalysis pa ON ups.UserId = pa.OwnerUserId
LEFT JOIN TagUsageAnalysis ta ON pa.PostId = ta.PostId
LEFT JOIN PostHistory ph ON ph.PostId = pa.PostId OR ph.UserId = ups.UserId
LEFT JOIN Votes v ON v.UserId = ups.UserId
LEFT JOIN Badges b ON b.UserId = ups.UserId
LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
LEFT JOIN Comments c ON c.PostId = pa.PostId
LEFT JOIN AggregateTagStats ats ON ats.TagName = 'performance';