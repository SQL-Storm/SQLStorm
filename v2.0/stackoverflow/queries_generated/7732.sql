-- {"query": "7732.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3340} 
WITH PostStats AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Body,
        p.LastActivityDate,
        u.Reputation as OwnerReputation,
        u.DisplayName as OwnerDisplayName,
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
        END as PostTypeName,
        COALESCE(p.AcceptedAnswerId, 0) as AcceptedAnswerId,
        COALESCE(p.ParentId, 0) as ParentId,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 0 
            THEN ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1) 
            ELSE 0 
        END as TagCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        PERCENT_RANK() OVER (ORDER BY p.CreationDate) as CreationPercentile,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as MovingAvgScore,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL 
            THEN 1 
            ELSE 0 
        END as HasAcceptedAnswer,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 
            THEN 1 
            ELSE 0 
        END as HasAnswers,
        CASE 
            WHEN p.CommentCount > 0 
            THEN 1 
            ELSE 0 
        END as HasComments,
        CASE 
            WHEN p.FavoriteCount > 0 
            THEN 1 
            ELSE 0 
        END as HasFavorites,
        CASE 
            WHEN p.Score > 0 AND p.ViewCount > 0 
            THEN p.Score * 1.0 / p.ViewCount 
            ELSE 0 
        END as ScorePerView,
        CASE 
            WHEN p.PostTypeId = 1 
            THEN EXTRACT(DAYS FROM (COALESCE(p.ClosedDate, CURRENT_TIMESTAMP) - p.CreationDate)) 
            ELSE 0 
        END as DaysToCloseOrCurrent,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 
            THEN 
                (SELECT AVG(a.Score) 
                 FROM Posts a 
                 WHERE a.ParentId = p.Id 
                 AND a.PostTypeId = 2 
                 AND a.Score IS NOT NULL) 
            ELSE NULL 
        END as AvgAnswerScore,
        CASE 
            WHEN p.PostTypeId = 1 
            THEN 
                (SELECT COUNT(*) 
                 FROM Votes v 
                 WHERE v.PostId = p.Id 
                 AND v.VoteTypeId = 5) 
            ELSE 0 
        END as FavoriteCountByVotes,
        REGEXP_REPLACE(p.Title, '[^a-zA-Z0-9\s]', '', 'g') as CleanTitle
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= '2010-01-01' 
    AND p.PostTypeId IN (1, 2) 
    AND (p.Score >= 0 OR p.Score IS NULL)
),
RankedPosts AS (
    SELECT 
        *,
        CASE 
            WHEN ScoreRank <= 100 THEN 'Top 100'
            WHEN ScoreRank <= 1000 THEN 'Top 1000'
            WHEN ScoreRank <= 10000 THEN 'Top 10000'
            ELSE 'Below 10k'
        END as ScoreTier,
        CASE 
            WHEN ViewRank <= 100 THEN 'Most Viewed Top 100'
            WHEN ViewRank <= 1000 THEN 'Most Viewed Top 1000'
            WHEN ViewRank <= 10000 THEN 'Most Viewed Top 10000'
            ELSE 'Below 10k Viewed'
        END as ViewTier,
        CASE 
            WHEN UserPostRank = 1 THEN 'Most Recent Post'
            WHEN UserPostRank = 2 THEN 'Second Most Recent Post'
            ELSE 'Other Post'
        END as PostOrder,
        COALESCE(
            (SELECT COUNT(DISTINCT bh.UserId) 
             FROM PostHistory bh 
             WHERE bh.PostId = PostId 
             AND bh.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9)
            ), 0) as EditCount,
        COALESCE(
            (SELECT COUNT(*)
             FROM Comments c
             WHERE c.PostId = PostId
             AND c.Score > 0
            ), 0) as PositiveComments,
        CASE 
            WHEN ABS(Score - COALESCE(PrevScore, Score)) > 10 THEN 'High Score Change'
            WHEN ABS(Score - COALESCE(NextScore, Score)) > 10 THEN 'High Score Change'
            ELSE 'Stable Score'
        END as ScoreChangeType,
        CASE 
            WHEN (Score - COALESCE(MovingAvgScore, Score)) > 50 THEN 'Above Moving Average'
            WHEN (Score - COALESCE(MovingAvgScore, Score)) < -50 THEN 'Below Moving Average'
            ELSE 'Near Moving Average'
        END as ScoreDeviation,
        (SELECT COUNT(*) 
         FROM Badges b 
         WHERE b.UserId = OwnerUserId 
         AND b.Date >= '2010-01-01'
         AND b.Class = 1) as GoldBadgesCount,
        COALESCE(
            (SELECT MIN(CreationDate)
             FROM PostHistory ph
             WHERE ph.PostId = PostId 
             AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
            ), CreationDate) as FirstEditDate,
        COALESCE(
            (SELECT MAX(CreationDate)
             FROM PostHistory ph
             WHERE ph.PostId = PostId 
             AND ph.PostHistoryTypeId IN (10, 11, 12, 13)
            ), '1900-01-01') as LastImportantActionDate
    FROM PostStats
),
AggregatedResults AS (
    SELECT 
        PostId,
        PostTypeName,
        OwnerUserId,
        OwnerReputation,
        OwnerDisplayName,
        Score,
        ViewCount,
        AnswerCount,
        CommentCount,
        FavoriteCount,
        Title,
        Tags,
        TagCount,
        ScorePerView,
        DaysToCloseOrCurrent,
        AvgAnswerScore,
        FavoriteCountByVotes,
        EditCount,
        PositiveComments,
        ScoreTier,
        ViewTier,
        PostOrder,
        ScoreChangeType,
        ScoreDeviation,
        GoldBadgesCount,
        FirstEditDate,
        LastImportantActionDate,
        CreationPercentile,
        UserPostRank,
        ScoreRank,
        ViewRank,
        MovingAvgScore,
        HasAcceptedAnswer,
        HasAnswers,
        HasComments,
        HasFavorites,
        CleanTitle,
        CASE 
            WHEN OwnerReputation > 100000 THEN 'Legendary'
            WHEN OwnerReputation > 10000 THEN 'Master'
            WHEN OwnerReputation > 1000 THEN 'Expert'
            WHEN OwnerReputation > 100 THEN 'Novice'
            ELSE 'Newbie'
        END as UserReputationLevel,
        CASE 
            WHEN TagCount > 5 THEN 'Rich Tagged'
            WHEN TagCount > 2 THEN 'Moderate Tagged'
            WHEN TagCount > 0 THEN 'Light Tagged'
            ELSE 'Untagged'
        END as TagLevel,
        CASE 
            WHEN Score >= 1000 THEN 'Virtuoso'
            WHEN Score >= 100 THEN 'Expert'
            WHEN Score >= 10 THEN 'Intermediate'
            WHEN Score >= 1 THEN 'Novice'
            ELSE 'Beginner'
        END as PostScoreLevel,
        CASE 
            WHEN ViewCount >= 10000 THEN 'Viral'
            WHEN ViewCount >= 1000 THEN 'Popular'
            WHEN ViewCount >= 100 THEN 'Notable'
            WHEN ViewCount >= 10 THEN 'Moderate'
            ELSE 'Low'
        END as ViewLevel,
        CASE 
            WHEN CommentCount >= 50 THEN 'Very Active'
            WHEN CommentCount >= 20 THEN 'Active'
            WHEN CommentCount >= 10 THEN 'Moderate'
            WHEN CommentCount >= 5 THEN 'Low Activity'
            ELSE 'Minimal'
        END as CommentActivityLevel,
        CASE 
            WHEN FavoriteCount >= 50 THEN 'Highly Favorited'
            WHEN FavoriteCount >= 20 THEN 'Favorited'
            WHEN FavoriteCount >= 10 THEN 'Moderately Favorited'
            WHEN FavoriteCount >= 5 THEN 'Slightly Favorited'
            ELSE 'Not Favorited'
        END as FavoriteLevel,
        CASE 
            WHEN ABS(Score - MovingAvgScore) >= 100 THEN 'Extreme Deviation'
            WHEN ABS(Score - MovingAvgScore) >= 50 THEN 'Significant Deviation'
            WHEN ABS(Score - MovingAvgScore) >= 10 THEN 'Minor Deviation'
            ELSE 'Minimal Deviation'
        END as DeviationLevel,
        -- Multiple outer joins to gather various derived information
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = PostId AND v.VoteTypeId IN (2, 3)) as TotalVotes,
        -- Using correlated subquery to get post history data
        (SELECT MAX(bh.PostHistoryTypeId) FROM PostHistory bh 
         WHERE bh.PostId = PostId 
         AND bh.PostHistoryTypeId IN (10, 11, 12, 13)) as LatestImportantAction,
        -- Complex calculation for time analysis
        EXTRACT(EPOCH FROM (LastImportantActionDate - FirstEditDate)) / 86400 as DaysBetweenFirstAndLastAction,
        -- String manipulation
        INITCAP(LEFT(Body, 50)) as BodyPreview,
        CASE 
            WHEN Body LIKE '%<code>%' THEN 'ContainsCode'
            WHEN Body LIKE '%<pre>%' THEN 'ContainsPreformatted'
            ELSE 'NoCode'
        END as CodePresence,
        -- NULL handling
        COALESCE(CleanTitle, 'No Title') as FinalTitle,
        -- Complex expression for ranking
        DENSE_RANK() OVER (ORDER BY ScorePerView DESC, ViewCount DESC) as CombinedRank
    FROM RankedPosts
)
-- Final query with all the elements
SELECT 
    ar.PostId,
    ar.PostTypeName,
    ar.OwnerDisplayName,
    ar.Score,
    ar.ViewCount,
    ar.AnswerCount,
    ar.CommentCount,
    ar.FavoriteCount,
    ar.Title,
    ar.Tags,
    ar.TagCount,
    ar.ScorePerView,
    ar.DaysToCloseOrCurrent,
    ar.AvgAnswerScore,
    ar.FavoriteCountByVotes,
    ar.EditCount,
    ar.PositiveComments,
    ar.ScoreTier,
    ar.ViewTier,
    ar.PostOrder,
    ar.ScoreChangeType,
    ar.ScoreDeviation,
    ar.GoldBadgesCount,
    ar.FirstEditDate,
    ar.LastImportantActionDate,
    ar.CreationPercentile,
    ar.UserPostRank,
    ar.ScoreRank,
    ar.ViewRank,
    ar.MovingAvgScore,
    ar.HasAcceptedAnswer,
    ar.HasAnswers,
    ar.HasComments,
    ar.HasFavorites,
    ar.UserReputationLevel,
    ar.TagLevel,
    ar.PostScoreLevel,
    ar.ViewLevel,
    ar.CommentActivityLevel,
    ar.FavoriteLevel,
    ar.DeviationLevel,
    ar.TotalVotes,
    ar.LatestImportantAction,
    ar.DaysBetweenFirstAndLastAction,
    ar.BodyPreview,
    ar.CodePresence,
    ar.FinalTitle,
    ar.CombinedRank,
    -- Complex set operation element with UNION (simulating a performance burden)
    (SELECT COUNT(*) FROM (VALUES (1), (2), (3)) t(n)) as DummyUnionCount,
    -- Using NULL logic 
    CASE 
        WHEN ar.Score IS NULL THEN 'NULL Score'
        WHEN ar.Score = 0 THEN 'Zero Score'
        WHEN ar.Score > 100 THEN 'High Score'
        ELSE 'Regular Score'
    END as ScoreClassification,
    -- Set operation - INTERSECT with another simple result set
    (SELECT COUNT(*) FROM (
        SELECT 'test1' UNION SELECT 'test2' UNION SELECT 'test3'
    ) t) as SetOperationCount,
    -- Final calculated column
    (ar.Score * ar.ViewCount) / NULLIF(ar.AnswerCount + 1, 0) as ScoreViewAnswerRatio,
    -- Window function with partitioning and ordering
    ROW_NUMBER() OVER (PARTITION BY ar.OwnerUserId ORDER BY ar.Score DESC, ar.CreationDate DESC) as RankPerUser,
    -- Another window function with framing
    AVG(ar.Score) OVER (ORDER BY ar.ViewCount ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) as ScoreMovingAvgByViews,
    -- Complex predicate
    CASE WHEN 
        (ar.Score > 100 OR ar.ViewCount > 1000 OR ar.CommentCount > 10 OR ar.AnswerCount > 5)
        AND ar.HasAnswers = 1
        AND ar.PostTypeName = 'Question'
    THEN 1 ELSE 0 END as HighImpactPost
FROM AggregatedResults ar
WHERE 
    ar.OwnerReputation > 100 
    AND (ar.Score IS NOT NULL OR ar.ViewCount IS NOT NULL)
    AND ar.PostScoreLevel IN ('Virtuoso', 'Expert', 'Intermediate')
    AND (ar.ViewLevel = 'Viral' OR ar.ViewLevel = 'Popular')
    AND ar.TagLevel IN ('Rich Tagged', 'Moderate Tagged')
    AND ar.FavoriteLevel IN ('Highly Favorited', 'Favorited')
    AND ar.DeviationLevel IN ('Extreme Deviation', 'Significant Deviation')
    AND ar.ScoreClassification IN ('High Score', 'Regular Score')
    AND ar.LatestImportantAction IS NOT NULL
    AND ar.HasAnswers = 1
    AND ar.HasComments = 1
    AND ar.HasAcceptedAnswer = 1
    AND ar.HasFavorites = 1
ORDER BY ar.Score DESC, ar.ViewCount DESC, ar.CreationPercentile DESC
LIMIT 1000;