-- {"query": "7914.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1656} 
WITH RECURSIVE PostHierarchy AS (
    SELECT 
        p.Id,
        p.ParentId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        0 as Level,
        CAST(p.Id AS VARCHAR(1000)) as Path
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL
    UNION ALL
    SELECT 
        p.Id,
        p.ParentId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        ph.Level + 1,
        ph.Path || '->' || CAST(p.Id AS VARCHAR(1000))
    FROM Posts p
    INNER JOIN PostHierarchy ph ON p.ParentId = ph.Id
    WHERE ph.Level < 5
),
RankedPosts AS (
    SELECT 
        ph.*,
        ROW_NUMBER() OVER (PARTITION BY ph.ParentId ORDER BY ph.CreationDate DESC) as rn,
        COUNT(*) OVER (PARTITION BY ph.ParentId) as ChildCount,
        AVG(ph.Score) OVER (PARTITION BY ph.ParentId) as AvgScore
    FROM PostHierarchy ph
),
PostStats AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        COALESCE(p.AcceptedAnswerId, 0) as AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        COALESCE(u.DisplayName, 'Unknown') as OwnerName,
        COALESCE(u.Reputation, 0) as OwnerReputation,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) as AgeInDays,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
DetailedComments AS (
    SELECT 
        c.Id,
        c.PostId,
        c.Score,
        c.Text,
        c.CreationDate,
        c.UserId,
        COALESCE(c.UserDisplayName, 'Anonymous') as UserName,
        CASE 
            WHEN c.Score > 10 THEN 'Highly Rated'
            WHEN c.Score > 0 THEN 'Positive'
            ELSE 'Neutral/Negative'
        END as CommentRating
    FROM Comments c
),
AggregatedData AS (
    SELECT 
        ps.Id,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.CreationDate,
        ps.OwnerUserId,
        ps.OwnerName,
        ps.OwnerReputation,
        ps.ScoreCategory,
        ps.AgeInDays,
        ps.AnswerCount,
        ps.CommentCount,
        ps.PostType,
        ps.AcceptedAnswerId,
        COALESCE(SUM(dc.Score) OVER (PARTITION BY ps.Id), 0) as TotalCommentScore,
        COUNT(dc.Id) OVER (PARTITION BY ps.Id) as CommentCountWithScore,
        AVG(dc.Score) OVER (PARTITION BY ps.Id) as AvgCommentScore,
        CASE 
            WHEN ps.AnswerCount > 0 AND ps.CommentCount > 0 THEN 'Active'
            WHEN ps.AnswerCount > 0 THEN 'HasAnswers'
            WHEN ps.CommentCount > 0 THEN 'HasComments'
            ELSE 'Inactive'
        END as EngagementLevel,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Posts p2 WHERE p2.ParentId = ps.Id AND p2.PostTypeId = 2 AND p2.Score > 100) THEN 'HighValueAnswers'
            ELSE 'NormalAnswers'
        END as AnswerQuality
    FROM PostStats ps
    LEFT JOIN DetailedComments dc ON ps.Id = dc.PostId
),
ComplexCalculations AS (
    SELECT *,
        CASE 
            WHEN Score > 0 AND AgeInDays > 30 THEN Score * (1.0 + (AgeInDays / 365.0) * 0.05)
            WHEN Score <= 0 AND AgeInDays > 30 THEN Score * (1.0 - (AgeInDays / 365.0) * 0.02)
            ELSE Score
        END as AdjustedScore,
        CASE 
            WHEN ViewCount > 1000 THEN 'HighTraffic'
            WHEN ViewCount > 100 THEN 'MediumTraffic'
            ELSE 'LowTraffic'
        END as TrafficLevel,
        CASE 
            WHEN Score > 50 AND AnswerCount > 5 THEN 'PopularQuestion'
            WHEN Score < 0 AND AnswerCount = 0 THEN 'ControversialNoAnswers'
            WHEN Score > 0 AND AnswerCount = 0 THEN 'GoodUnanswered'
            ELSE 'Standard'
        END as QuestionClassification,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ad.Id AND v.VoteTypeId IN (1, 2)),
            0
        ) as TotalVotes,
        COALESCE(
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ad.OwnerUserId AND b.Class = 1),
            0
        ) as GoldBadges
    FROM AggregatedData ad
)
SELECT 
    cd.Id,
    cd.Title,
    cd.Score,
    cd.ViewCount,
    cd.CreationDate,
    cd.OwnerName,
    cd.OwnerReputation,
    cd.ScoreCategory,
    cd.AgeInDays,
    cd.AnswerCount,
    cd.CommentCount,
    cd.PostType,
    cd.AcceptedAnswerId,
    cd.TotalCommentScore,
    cd.CommentCountWithScore,
    cd.AvgCommentScore,
    cd.EngagementLevel,
    cd.AnswerQuality,
    cd.AdjustedScore,
    cd.TrafficLevel,
    cd.QuestionClassification,
    cd.TotalVotes,
    cd.GoldBadges,
    CASE 
        WHEN cd.AdjustedScore > 100 AND cd.ViewCount > 500 THEN 'Trending'
        WHEN cd.AdjustedScore > 50 AND cd.ViewCount > 200 THEN 'Popular'
        WHEN cd.AdjustedScore > 0 AND cd.ViewCount > 100 THEN 'Moderate'
        ELSE 'Low'
    END as TrendingCategory
FROM ComplexCalculations cd
WHERE cd.Id IN (
    SELECT Id FROM (
        SELECT p.Id, COUNT(*) as c
        FROM Posts p
        INNER JOIN PostHistory ph ON p.Id = ph.PostId
        WHERE p.PostTypeId = 1 AND ph.PostHistoryTypeId IN (1, 2, 3)
        GROUP BY p.Id
        HAVING COUNT(*) > 5
    ) ranked
)
    AND cd.Score BETWEEN (
        SELECT AVG(Score) - STDDEV(Score) 
        FROM Posts 
        WHERE PostTypeId = 1 AND Score IS NOT NULL
    ) AND (
        SELECT AVG(Score) + STDDEV(Score) 
        FROM Posts 
        WHERE PostTypeId = 1 AND Score IS NOT NULL
    )
    AND cd.OwnerReputation > (
        SELECT AVG(Reputation) 
        FROM Users
    )
    AND (
        cd.QuestionClassification = 'PopularQuestion' 
        OR cd.TrafficLevel = 'HighTraffic'
        OR cd.GoldBadges > 0
    )
ORDER BY cd.AdjustedScore DESC, cd.ViewCount DESC
LIMIT 1000;