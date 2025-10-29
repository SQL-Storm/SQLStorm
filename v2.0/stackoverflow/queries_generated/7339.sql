-- {"query": "7339.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2217} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT b.Id) as TotalBadges,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedQuestions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPosts DESC) as RankByReputation,
        DENSE_RANK() OVER (ORDER BY TotalPosts DESC) as RankByPostCount,
        NTILE(100) OVER (ORDER BY Reputation) as PercentileRank
    FROM UserActivityStats
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Upvoted'
            WHEN p.Score > 50 THEN 'Moderately Upvoted'
            WHEN p.Score > 0 THEN 'Neutral'
            WHEN p.Score < 0 THEN 'Downvoted'
            ELSE 'Unrated'
        END as ScoreCategory,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(string_to_array(trim(trim(p.Tags, '<>'), '><'), '><'), 1)
            ELSE 0
        END as TagCount,
        LEFT(p.Title, 50) as TitleShort,
        LENGTH(p.Body) as BodyLength,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
),
ComplexPostAnalysis AS (
    SELECT 
        pa.*,
        COALESCE(
            (SELECT COUNT(*) 
             FROM PostHistory ph 
             WHERE ph.PostId = pa.PostId 
             AND ph.PostHistoryTypeId IN (1, 4, 6)), 0
        ) as EditCount,
        (
            SELECT COUNT(*) 
            FROM Votes v 
            WHERE v.PostId = pa.PostId 
            AND v.VoteTypeId IN (2, 3)
        ) as VoteCount,
        (
            SELECT COUNT(*) 
            FROM Comments c 
            WHERE c.PostId = pa.PostId
        ) as CommentCountOnPost,
        (
            SELECT AVG(v.Score) 
            FROM Votes v 
            WHERE v.PostId = pa.PostId
        ) as AvgVoteScore,
        CASE 
            WHEN pa.PostTypeId = 1 THEN 
                (SELECT COUNT(*) 
                 FROM Posts a 
                 WHERE a.ParentId = pa.PostId 
                 AND a.PostTypeId = 2)
            ELSE 0
        END as AnswerCountForQuestion,
        CASE 
            WHEN pa.PostTypeId = 1 AND pa.Score > 0 THEN 
                (SELECT COUNT(*) 
                 FROM Posts a 
                 WHERE a.ParentId = pa.PostId 
                 AND a.PostTypeId = 2
                 AND a.Score > 0)
            ELSE 0
        END as PositiveAnswerCountForQuestion,
        ROW_NUMBER() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.Score DESC) as ScoreRankWithinUser,
        RANK() OVER (ORDER BY pa.Score DESC) as OverallScoreRank,
        PERCENT_RANK() OVER (ORDER BY pa.Score) as ScorePercentile,
        AVG(pa.Score) OVER (PARTITION BY pa.PostTypeId) as AvgScoreByType
    FROM PostAnalysis pa
),
FinalPostAnalysis AS (
    SELECT 
        cpa.*,
        (
            SELECT u.DisplayName 
            FROM Users u 
            WHERE u.Id = cpa.OwnerUserId
        ) as OwnerDisplayName,
        (
            SELECT u.Reputation 
            FROM Users u 
            WHERE u.Id = cpa.OwnerUserId
        ) as OwnerReputation,
        (
            SELECT COUNT(*)
            FROM Posts p_inner 
            WHERE p_inner.OwnerUserId = cpa.OwnerUserId
            AND p_inner.PostTypeId = 1
            AND (p_inner.ClosedDate IS NULL OR p_inner.ClosedDate > '2020-01-01')
            AND p_inner.CreationDate >= '2015-01-01'
        ) as ActiveQuestionsCount,
        CASE 
            WHEN cpa.PostTypeId = 1 THEN 
                (
                    SELECT COUNT(*)
                    FROM Posts p_inner 
                    WHERE p_inner.ParentId = cpa.PostId 
                    AND p_inner.PostTypeId = 2
                    AND p_inner.CreationDate >= '2015-01-01'
                )
            ELSE 0
        END as AnswersToThisQuestion,
        (
            SELECT MAX(ph.CreationDate)
            FROM PostHistory ph
            WHERE ph.PostId = cpa.PostId
            AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
        ) as LastActivityDateInHistory,
        (
            SELECT CASE 
                WHEN COUNT(*) > 0 THEN 'Yes' 
                ELSE 'No' 
            END
            FROM Votes v
            WHERE v.PostId = cpa.PostId
            AND v.VoteTypeId = 5
        ) as IsBookmarked,
        CASE 
            WHEN cpa.TagCount LIKE ('%java%') OR cpa.TagCount LIKE ('%python%') THEN 'Popular'
            WHEN cpa.TagCount LIKE ('%c%') OR cpa.TagCount LIKE ('%cpp%') THEN 'System'
            ELSE 'Other'
        END as ProgrammingCategory
    FROM ComplexPostAnalysis cpa
)
SELECT 
    fpa.PostId,
    fpa.TitleShort,
    fpa.OwnerDisplayName,
    fpa.OwnerReputation,
    fpa.Score,
    fpa.ViewCount,
    fpa.EditCount,
    fpa.VoteCount,
    fpa.CommentCountOnPost,
    fpa.TagCount,
    fpa.ScoreCategory,
    fpa.DaysSinceCreation,
    CASE 
        WHEN fpa.DaysSinceCreation < 30 THEN 'New'
        WHEN fpa.DaysSinceCreation BETWEEN 30 AND 365 THEN 'Medium'
        WHEN fpa.DaysSinceCreation > 365 THEN 'Established'
        ELSE 'Unknown'
    END as PostAgeCategory,
    fpa.ActiveQuestionsCount,
    fpa.AnswersToThisQuestion,
    fpa.IsBookmarked,
    fpa.ProgrammingCategory,
    fpa.ScoreRankWithinUser,
    fpa.OverallScoreRank,
    fpa.ScorePercentile,
    fpa.AvgScoreByType,
    (
        SELECT COUNT(*) 
        FROM RankedUsers ru 
        WHERE ru.Reputation > fpa.OwnerReputation
    ) as UsersWithHigherReputation,
    (
        SELECT COUNT(*) 
        FROM RankedUsers ru 
        WHERE ru.TotalPosts > fpa.ActiveQuestionsCount
    ) as UsersWithMoreQuestions,
    (
        SELECT AVG(ru.Reputation) 
        FROM RankedUsers ru 
        WHERE ru.RankByReputation <= 1000
    ) as Top1000AvgReputation,
    (
        SELECT COUNT(*) 
        FROM FinalPostAnalysis fpa2 
        WHERE fpa2.OwnerUserId = fpa.OwnerUserId
    ) as TotalPostsByOwner,
    (
        SELECT STRING_AGG(DISTINCT p2.Tags, ', ')
        FROM Posts p2 
        WHERE p2.OwnerUserId = fpa.OwnerUserId 
        AND p2.Tags IS NOT NULL
        LIMIT 10
    ) as SampleTagsFromOwner,
    CONCAT(
        fpa.TitleShort, 
        ' - ', 
        CASE 
            WHEN fpa.Score > 100 THEN 'Elite'
            WHEN fpa.Score > 50 THEN 'Popular'
            WHEN fpa.Score > 0 THEN 'Standard'
            ELSE 'Low'
        END,
        ' Q',
        fpa.AnswersToThisQuestion,
        '/',
        fpa.VoteCount
    ) as PostIdentifier
FROM FinalPostAnalysis fpa
WHERE fpa.PostTypeId IN (1, 2)
  AND fpa.Score BETWEEN 0 AND 1000
  AND fpa.DaysSinceCreation >= 0
  AND fpa.ActiveQuestionsCount IS NOT NULL
  AND fpa.AnswersToThisQuestion >= 0
  AND (fpa.OwnerReputation IS NULL OR fpa.OwnerReputation > 1)
  AND (
    fpa.ProgrammingCategory IN ('Popular', 'System', 'Other')
    OR fpa.Tags IS NOT NULL
  )
  AND (
    (fpa.PostTypeId = 1 AND fpa.AnswersToThisQuestion IS NOT NULL)
    OR (fpa.PostTypeId = 2 AND fpa.AnswersToThisQuestion IS NULL)
  )
  AND CONCAT(
    fpa.TitleShort, 
    ' - ', 
    CASE 
        WHEN fpa.Score > 100 THEN 'Elite'
        WHEN fpa.Score > 50 THEN 'Popular'
        WHEN fpa.Score > 0 THEN 'Standard'
        ELSE 'Low'
    END,
    ' Q',
    fpa.AnswersToThisQuestion,
    '/',
    fpa.VoteCount
  ) IS NOT NULL
ORDER BY 
    fpa.Score DESC,
    fpa.ViewCount DESC,
    fpa.DaysSinceCreation ASC
LIMIT 10000;