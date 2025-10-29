-- {"query": "7419.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2315} 
WITH UserActivityStats AS (
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
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Advanced'
            WHEN u.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) as QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) as AnswerCount,
        AVG(CAST(p.Score AS FLOAT)) as AvgPostScore,
        STRING_AGG(DISTINCT p.Tags, ';') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        NTILE(4) OVER (ORDER BY p.Score) as ScoreQuartile,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score IS NOT NULL
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END as TagType,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'), 0) as UsageCount,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as AvgScoreForTag,
        STRING_AGG(DISTINCT p.OwnerUserId, ',') as TagUsers
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsRequired
),
ComplexUserAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.ReputationLevel,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.AvgPostScore,
        uas.AllTags,
        CASE 
            WHEN uas.CommentCount > 0 AND uas.BadgeCount > 0 THEN 'Active Contributor'
            WHEN uas.PostCount > 10 AND uas.Reputation > 1000 THEN 'Regular Member'
            WHEN uas.QuestionCount > 5 THEN 'Questioner'
            WHEN uas.AnswerCount > 10 THEN 'Answerer'
            ELSE 'Inactive User'
        END as UserCategory,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = uas.UserId AND p.Score > 100), 0) as HighScorePosts,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = uas.UserId AND p.CreationDate > '2021-01-01'), 0) as RecentPosts,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = uas.UserId AND v.VoteTypeId = 2) as UpvotesGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = uas.UserId AND v.VoteTypeId = 3) as DownvotesGiven,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = uas.UserId AND b.Class = 1) as GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = uas.UserId AND b.Class = 2) as SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = uas.UserId AND b.Class = 3) as BronzeBadges
    FROM UserActivityStats uas
),
FinalAnalysis AS (
    SELECT 
        cua.UserId,
        cua.DisplayName,
        cua.Reputation,
        cua.ReputationLevel,
        cua.PostCount,
        cua.CommentCount,
        cua.BadgeCount,
        cua.QuestionCount,
        cua.AnswerCount,
        cua.AvgPostScore,
        cua.UserCategory,
        cua.HighScorePosts,
        cua.RecentPosts,
        cua.UpvotesGiven,
        cua.DownvotesGiven,
        cua.GoldBadges,
        cua.SilverBadges,
        cua.BronzeBadges,
        CASE 
            WHEN cua.Reputation > 10000 AND cua.BadgeCount > 50 THEN 'Legend'
            WHEN cua.Reputation > 5000 AND cua.PostCount > 100 THEN 'Veteran'
            WHEN cua.GoldBadges > 10 THEN 'Gold Contributor'
            WHEN cua.SilverBadges > 20 THEN 'Silver Contributor'
            ELSE 'Regular Contributor'
        END as ContributionTier,
        (SELECT STRING_AGG(DISTINCT p.Title, ', ') 
         FROM Posts p 
         WHERE p.OwnerUserId = cua.UserId 
         AND p.PostTypeId = 1 
         AND p.Score > 50
         LIMIT 5) as HighQualityQuestions,
        (SELECT STRING_AGG(DISTINCT p.Title, ', ') 
         FROM Posts p 
         WHERE p.OwnerUserId = cua.UserId 
         AND p.PostTypeId = 2 
         AND p.Score > 20
         LIMIT 5) as HighQualityAnswers
    FROM ComplexUserAnalysis cua
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.ReputationLevel,
    fa.PostCount,
    fa.CommentCount,
    fa.BadgeCount,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.AvgPostScore,
    fa.UserCategory,
    fa.HighScorePosts,
    fa.RecentPosts,
    fa.UpvotesGiven,
    fa.DownvotesGiven,
    fa.GoldBadges,
    fa.SilverBadges,
    fa.BronzeBadges,
    fa.ContributionTier,
    fa.HighQualityQuestions,
    fa.HighQualityAnswers,
    CASE 
        WHEN fa.Reputation > 1000 AND fa.PostCount > 50 AND fa.CommentCount > 10 THEN 'Very Active'
        WHEN fa.Reputation > 500 AND fa.PostCount > 25 THEN 'Active'
        ELSE 'Moderate'
    END as ActivityLevel,
    COALESCE(ta.TagName, 'No Tags') as MostCommonTag,
    COALESCE(ta.Count, 0) as TagCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fa.UserId AND p.CreationDate BETWEEN '2022-01-01' AND '2023-12-31') as Posts2022to2023,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = fa.UserId AND v.CreationDate BETWEEN '2022-01-01' AND '2023-12-31') as Votes2022to2023,
    COALESCE((SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = fa.UserId), 0) as AvgUserScore,
    COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.UserId = fa.UserId), 0) as TotalComments,
    (SELECT COUNT(*) FROM Posts p1 JOIN Posts p2 ON p1.Id = p2.ParentId WHERE p1.OwnerUserId = fa.UserId) as AnsweredQuestions,
    STRING_AGG(DISTINCT CONCAT(fa.DisplayName, ' (', fa.Reputation, ')'), ' | ') OVER (ORDER BY fa.Reputation DESC ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) as ReputationNeighbors,
    ROW_NUMBER() OVER (ORDER BY fa.Reputation DESC) as RankByReputation,
    DENSE_RANK() OVER (ORDER BY fa.PostCount DESC) as RankByPostCount,
    NTILE(10) OVER (ORDER BY fa.BadgeCount DESC) as BadgeDecile,
    CASE 
        WHEN fa.Reputation >= 1000 AND fa.PostCount >= 50 AND fa.BadgeCount >= 10 THEN 1
        WHEN fa.Reputation >= 1000 AND fa.PostCount >= 25 THEN 2
        ELSE 3
    END as CommunityStatus,
    CASE 
        WHEN fa.Reputation > 5000 THEN 
            CONCAT('Top ', CAST(ROW_NUMBER() OVER (ORDER BY fa.Reputation DESC) AS VARCHAR), ' Reputation User')
        ELSE 
            'Standard User'
    END as UserStatus,
    NULLIF('User: ' || fa.DisplayName || ' - Reputations: ' || CAST(fa.Reputation AS VARCHAR) || ' - Posts: ' || CAST(fa.PostCount AS VARCHAR) || ' - Badges: ' || CAST(fa.BadgeCount AS VARCHAR), 'User:  - Reputations:  - Posts:  - Badges: ') as UserSummary
FROM FinalAnalysis fa
LEFT JOIN TagAnalysis ta ON ta.UsageCount = (
    SELECT MAX(UsageCount) 
    FROM TagAnalysis 
    WHERE TagUsers LIKE '%' || fa.UserId || '%'
)
WHERE fa.Reputation > 100 
  AND (fa.PostCount > 0 OR fa.CommentCount > 0 OR fa.BadgeCount > 0)
  AND fa.ContributionTier IN ('Legend', 'Veteran', 'Gold Contributor', 'Silver Contributor', 'Regular Contributor')
ORDER BY fa.Reputation DESC, fa.PostCount DESC, fa.BadgeCount DESC
LIMIT 1000;