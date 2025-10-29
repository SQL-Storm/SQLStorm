WITH UserActivity AS (
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
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        STRING_AGG(DISTINCT p.Tags, ', ') as AllTags,
        AVG(p.Score) as AvgPostScore,
        MAX(p.ViewCount) as MaxViewCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.Body,
        p.AcceptedAnswerId,
        p.FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
            WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
            WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
            ELSE 'Unknown'
        END as PostType,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Moderate'
            ELSE 'Low'
        END as Popularity,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as NewestPost,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
        NTILE(10) OVER (ORDER BY p.Score) as ScoreDecile,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as Engagement,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = p.PostTypeId) * 1.5 THEN 'Above Average'
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = p.PostTypeId) * 0.5 THEN 'Below Average'
            ELSE 'Average'
        END as ScoreCategory,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p2 
             WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.Score > p.Score),
            0
        ) as BetterAnswersCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= DATE '2022-01-01'
),
BadgeAnalysis AS (
    SELECT 
        b.UserId,
        b.Name as BadgeName,
        b.Date as BadgeDate,
        b.Class,
        COUNT(*) OVER (PARTITION BY b.UserId, b.Class) as ClassBadgeCount,
        FLOOR(EXTRACT(EPOCH FROM (b.Date - MIN(b.Date) OVER (PARTITION BY b.UserId))) / 86400) * 1 AS DaysSinceFirstBadge,
        CASE 
            WHEN b.Class = 1 THEN 'Gold'
            WHEN b.Class = 2 THEN 'Silver'
            WHEN b.Class = 3 THEN 'Bronze'
            ELSE 'Unknown'
        END as BadgeTier,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) as RecentBadge,
        CASE 
            WHEN b.Class = 1 AND COUNT(*) OVER (PARTITION BY b.UserId, b.Class) >= 3 THEN 'Multiple Gold'
            WHEN b.Class = 2 AND COUNT(*) OVER (PARTITION BY b.UserId, b.Class) >= 5 THEN 'Multiple Silver'
            ELSE 'Single or Few'
        END as BadgeConsistency
    FROM Badges b
    WHERE b.Date >= DATE '2021-01-01'
),
ComplexPostAnalysis AS (
    SELECT 
        ps.Id as PostId,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.Title,
        ps.Tags,
        ps.Popularity,
        ps.ScoreRank,
        ps.NewestPost,
        ps.ViewRank,
        ps.PrevScore,
        ps.NextScore,
        ps.ScoreDecile,
        ps.Engagement,
        ps.ScoreCategory,
        ps.BetterAnswersCount,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        u.Views as OwnerViews,
        u.UpVotes as OwnerUpVotes,
        u.DownVotes as OwnerDownVotes,
        u.AccountId as OwnerAccountId,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM Votes v 
                WHERE v.PostId = ps.Id AND v.VoteTypeId IN (1, 2) AND v.UserId IS NOT NULL
            ) THEN 'Has Votes'
            ELSE 'No Votes'
        END as VoteStatus,
        CASE 
            WHEN ps.PostTypeId = 1 THEN 
                CASE 
                    WHEN ps.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
                    WHEN ps.AnswerCount > 0 THEN 'Has Answers'
                    ELSE 'No Answers'
                END
            ELSE 'Not a Question'
        END as QuestionStatus,
        CASE 
            WHEN ps.Title IS NOT NULL AND LENGTH(ps.Title) > 50 THEN 'Long Title'
            WHEN ps.Title IS NOT NULL AND LENGTH(ps.Title) < 20 THEN 'Short Title'
            ELSE 'Medium Title'
        END as TitleLength,
        CASE 
            WHEN ps.Tags IS NOT NULL AND LENGTH(ps.Tags) > 50 THEN 'Many Tags'
            WHEN ps.Tags IS NOT NULL AND LENGTH(ps.Tags) < 20 THEN 'Few Tags'
            ELSE 'Medium Tags'
        END as TagDensity,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p 
             WHERE p.ParentId = ps.Id AND p.PostTypeId = 2 AND p.CreationDate > ps.CreationDate),
            0
        ) as AnswerCountAfterPost,
        COALESCE(
            (SELECT MAX(v.CreationDate) FROM Votes v 
             WHERE v.PostId = ps.Id AND v.UserId IS NOT NULL AND v.VoteTypeId = 2),
            ps.CreationDate
        ) as LastUpvoteDate,
        FLOOR(EXTRACT(EPOCH FROM ((COALESCE(
            (SELECT MAX(v.CreationDate) FROM Votes v 
             WHERE v.PostId = ps.Id AND v.UserId IS NOT NULL AND v.VoteTypeId = 2),
            ps.CreationDate
        )) - ps.CreationDate)) / 86400) * 1 AS DaysSinceLastUpvote,
        CASE 
            WHEN ps.Score < 0 THEN 'Negative Score'
            WHEN ps.Score > 100 THEN 'High Score'
            WHEN ps.Score > 25 THEN 'Moderate Score'
            ELSE 'Low Score'
        END as ScoreLevel,
        ('Post #' || ps.Id || ' by ' || u.DisplayName || ' with score ' || ps.Score || ' and ' || ps.ViewCount || ' views') as PostSummary,
        ROW_NUMBER() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate DESC) as UserPostRank,
        LAG(ps.Score, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) as OwnerPrevScore,
        CASE 
            WHEN ps.Score > LAG(ps.Score, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) THEN 'Improved'
            WHEN ps.Score < LAG(ps.Score, 1) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) THEN 'Declined'
            ELSE 'Stable'
        END as ScoreChangeStatus,
        ps.CreationDate as CreationDate
    FROM PostStats ps
    JOIN Users u ON ps.OwnerUserId = u.Id
    WHERE ps.Score > 0
)
SELECT 
    ca.PostId,
    ca.PostTypeId,
    ca.OwnerUserId,
    ca.Score,
    ca.ScoreRank,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.Title,
    ca.Tags,
    ca.Popularity,
    ca.Engagement,
    ca.ScoreCategory,
    ca.BetterAnswersCount,
    ca.OwnerName,
    ca.OwnerReputation,
    ca.OwnerViews,
    ca.OwnerUpVotes,
    ca.OwnerDownVotes,
    ca.VoteStatus,
    ca.QuestionStatus,
    ca.TitleLength,
    ca.TagDensity,
    ca.AnswerCountAfterPost,
    ca.DaysSinceLastUpvote,
    ca.ScoreLevel,
    ca.PostSummary,
    ca.ScoreChangeStatus,
    COUNT(*) OVER () as TotalPosts,
    AVG(ca.Score) OVER (PARTITION BY ca.OwnerUserId) as OwnerAvgScore,
    COUNT(*) OVER (PARTITION BY ca.OwnerUserId) as OwnerPostCount,
    PERCENT_RANK() OVER (ORDER BY ca.Score) as ScorePercentile,
    CUME_DIST() OVER (ORDER BY ca.ViewCount) as ViewPercentage,
    CASE 
        WHEN ca.OwnerReputation > (SELECT AVG(Reputation) FROM Users) * 2 THEN 'High Rep User'
        WHEN ca.OwnerReputation > (SELECT AVG(Reputation) FROM Users) THEN 'Above Avg User'
        ELSE 'Below Avg User'
    END as ReputationLevel,
    CASE 
        WHEN ca.Popularity = 'Viral' AND ca.Score > 50 THEN 'High Impact'
        WHEN ca.Popularity = 'Popular' AND ca.Score > 25 THEN 'Medium Impact'
        WHEN ca.ViewCount > 100 THEN 'High Visibility'
        ELSE 'Regular'
    END as ImpactLevel,
    -- RunningTagList rewritten to use a correlated subquery to emulate a running aggregate (more portable)
    (
      SELECT STRING_AGG(t.Tags, ', ')
      FROM ComplexPostAnalysis t
      WHERE (t.ViewCount > ca.ViewCount)
         OR (t.ViewCount = ca.ViewCount AND t.PostId <= ca.PostId)
    ) as RunningTagList,
    NTH_VALUE(ca.Title, 1) OVER (ORDER BY ca.Score DESC) as HighestScoredTitle,
    MAX(ca.ViewCount) OVER (ORDER BY ca.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as CumulativeMaxViews,
    CASE 
        WHEN ca.BetterAnswersCount > 10 THEN 'Many Better Answers'
        WHEN ca.BetterAnswersCount > 5 THEN 'Some Better Answers'
        ELSE 'Few Better Answers'
    END as BetterAnswersCategory,
    DENSE_RANK() OVER (ORDER BY ca.OwnerReputation DESC) as OwnerReputationRank,
    ROW_NUMBER() OVER (ORDER BY ca.OwnerReputation DESC, ca.Score DESC) as OverallRank,
    CASE 
        WHEN ca.Score > 0 AND ca.ScoreRank <= 10 THEN 'Top 10 Score'
        WHEN ca.Score >= 0 THEN 'Positive Score'
        ELSE 'Negative Score'
    END as ScoreCategoryRanking,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p 
         WHERE p.ParentId = ca.PostId AND p.PostTypeId = 2 AND p.Score > ca.Score),
        0
    ) as SuperiorAnswersCount,
    CASE 
        WHEN ca.PostTypeId = 1 AND ca.AnswerCount > 0 THEN 
            CAST(ca.AnswerCount AS FLOAT) / NULLIF(ca.AnswerCount + ca.CommentCount, 0)
        ELSE NULL
    END as AnswerToCommentRatio,
    CASE 
        WHEN ca.Tags IS NOT NULL AND EXISTS (
            SELECT 1 FROM (SELECT REGEXP_SPLIT_TO_TABLE(ca.Tags, '>') AS t) s WHERE s.t LIKE '%<%'
        ) THEN 'Has Nested Tags'
        ELSE 'No Nested Tags'
    END as TagStructure,
    COALESCE(
        (SELECT COUNT(DISTINCT UserId) FROM Votes v 
         WHERE v.PostId = ca.PostId AND v.VoteTypeId = 2),
        0
    ) as UpvoteCount,
    COALESCE(
        (SELECT COUNT(DISTINCT UserId) FROM Votes v 
         WHERE v.PostId = ca.PostId AND v.VoteTypeId = 3),
        0
    ) as DownvoteCount,
    CASE 
        WHEN (COALESCE((SELECT COUNT(DISTINCT UserId) FROM Votes v 
                        WHERE v.PostId = ca.PostId AND v.VoteTypeId = 2), 0) +
              COALESCE((SELECT COUNT(DISTINCT UserId) FROM Votes v 
                        WHERE v.PostId = ca.PostId AND v.VoteTypeId = 3), 0)) > 50 THEN 'High Voter Engagement'
        WHEN (COALESCE((SELECT COUNT(DISTINCT UserId) FROM Votes v 
                        WHERE v.PostId = ca.PostId AND v.VoteTypeId = 2), 0) +
              COALESCE((SELECT COUNT(DISTINCT UserId) FROM Votes v 
                        WHERE v.PostId = ca.PostId AND v.VoteTypeId = 3), 0)) > 10 THEN 'Moderate Voter Engagement'
        ELSE 'Low Voter Engagement'
    END as EngagementLevel
FROM ComplexPostAnalysis ca
WHERE ca.OwnerAccountId IS NOT NULL
  AND (ca.Score > 5 OR ca.ViewCount > 50 OR ca.AnswerCount > 0)
  AND ca.OwnerReputation > 500
  AND ca.Title IS NOT NULL AND LENGTH(ca.Title) > 0
ORDER BY ca.Score DESC, ca.ViewCount DESC, ca.CreationDate DESC
LIMIT 1000;