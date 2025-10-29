-- {"query": "2155.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1622} 
WITH RankedAnswers AS (
    SELECT
        a.Id,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        a.Body,
        ROW_NUMBER() OVER(PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank,
        COUNT(*) OVER(PARTITION BY a.ParentId) AS TotalAnswers
    FROM Posts a
    WHERE a.PostTypeId = 2 -- answers
), QuestionStats AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        COALESCE(q.AnswerCount, 0) AS AnswerCount,
        COALESCE(q.FavoriteCount, 0) AS FavoriteCount,
        -- Extract first tag from Tags string assuming format: <tag1><tag2><tag3>
        CASE
           WHEN q.Tags IS NOT NULL AND LENGTH(TRIM(q.Tags)) > 2 THEN 
               substring(
                   substring(q.Tags from 2 for LENGTH(q.Tags) - 2)
                   from 1 for strpos(substring(q.Tags from 2 for LENGTH(q.Tags) - 2), '>') - 1
               )
           ELSE NULL
        END AS FirstTag
    FROM Posts q
    WHERE q.PostTypeId = 1 -- questions
), BadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
), UserAggregates AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COALESCE(bc.GoldBadges, 0) AS GoldBadges,
        COALESCE(bc.SilverBadges, 0) AS SilverBadges,
        COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
        u.UpVotes,
        u.DownVotes,
        -- Reputation per day since account creation
        CASE 
            WHEN CURRENT_DATE > CAST(u.CreationDate AS date) 
            THEN u.Reputation::float / (CURRENT_DATE - CAST(u.CreationDate AS date))
            ELSE NULL
        END AS ReputationPerDay,
        -- Simple string expression: reverse DisplayName (if not null)
        CASE WHEN u.DisplayName IS NOT NULL THEN reverse(u.DisplayName) ELSE NULL END AS ReverseDisplayName
    FROM Users u
    LEFT JOIN BadgeCounts bc ON u.Id = bc.UserId
), QuestionAnswerLinks AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.OwnerUserId AS QuestionOwner,
        uagg.DisplayName AS QuestionOwnerName,
        uagg.Reputation AS QuestionOwnerReputation,
        uagg.GoldBadges,
        uagg.SilverBadges,
        uagg.BronzeBadges,
        ra.Id AS TopAnswerId,
        ra.Score AS TopAnswerScore,
        ra.CreationDate AS TopAnswerCreation,
        ra.OwnerUserId AS TopAnswerOwner,
        uagg_top.DisplayName AS TopAnswerOwnerName,
        uagg_top.Reputation AS TopAnswerOwnerReputation,
        ra.TotalAnswers,
        -- Calculate difference in days between question and top answer
        EXTRACT(EPOCH FROM (ra.CreationDate - q.CreationDate))/86400.0 AS DaysToTopAnswer,
        q.FirstTag
    FROM QuestionStats q
    LEFT JOIN RankedAnswers ra ON ra.QuestionId = q.QuestionId AND ra.AnswerRank = 1
    LEFT JOIN UserAggregates uagg ON uagg.Id = q.OwnerUserId
    LEFT JOIN UserAggregates uagg_top ON uagg_top.Id = ra.OwnerUserId
    WHERE q.AnswerCount > 0
), CloseReasonCounts AS (
    SELECT
        cht.Name AS CloseReasonName,
        COUNT(*) AS CloseCount
    FROM PostHistory ph
    JOIN PostHistoryTypes chtype ON ph.PostHistoryTypeId = chtype.Id
    LEFT JOIN CloseReasonTypes cht ON ph.Comment::int = cht.Id
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed events
    GROUP BY cht.Name
), UserQuestionPairs AS (
    SELECT DISTINCT
        u.Id AS UserId,
        q.Id AS QuestionId
    FROM Users u
    JOIN Posts q ON q.PostTypeId = 1 AND q.OwnerUserId = u.Id
), FilteredPosts AS (
    -- Select recent questions and their answers with complicated predicates and NULL logic
    SELECT p.*
    FROM Posts p
    WHERE (p.PostTypeId = 1 AND p.CreationDate >= NOW() - interval '1 year' AND p.AnswerCount > 2)
       OR (p.PostTypeId = 2 AND EXISTS (
           SELECT 1 FROM Posts pq WHERE pq.Id = p.ParentId AND pq.CreationDate >= NOW() - interval '1 year'
       ))
),
-- Window function example: compute cumulative average score for answers per question ordered by creation date
AnswerWindowStats AS (
    SELECT
        fa.Id,
        fa.ParentId,
        fa.Score,
        fa.CreationDate,
        AVG(fa.Score) OVER (PARTITION BY fa.ParentId ORDER BY fa.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAvgAnswerScore,
        ROW_NUMBER() OVER (PARTITION BY fa.ParentId ORDER BY fa.Score DESC) AS RankByScore
    FROM FilteredPosts fa
    WHERE fa.PostTypeId = 2
),
-- Complex correlated subquery: find for each question the answer with the max cumulative average score
BestCumulativeAnswer AS (
    SELECT DISTINCT ON (aw.ParentId)
        aw.ParentId AS QuestionId,
        aw.Id AS AnswerId,
        aw.CumulativeAvgAnswerScore
    FROM AnswerWindowStats aw
    ORDER BY aw.ParentId, aw.CumulativeAvgAnswerScore DESC, aw.CreationDate
)
SELECT
    qal.QuestionId,
    qal.Title,
    qal.QuestionCreation,
    qal.QuestionScore,
    qal.ViewCount,
    qal.AnswerCount,
    qal.FavoriteCount,
    qal.QuestionOwner,
    qal.QuestionOwnerName,
    qal.QuestionOwnerReputation,
    qal.GoldBadges,
    qal.SilverBadges,
    qal.BronzeBadges,
    qal.TopAnswerId,
    qal.TopAnswerScore,
    qal.TopAnswerCreation,
    qal.TopAnswerOwner,
    qal.TopAnswerOwnerName,
    qal.TopAnswerOwnerReputation,
    qal.TotalAnswers,
    qal.DaysToTopAnswer,
    qal.FirstTag,
    bca.AnswerId AS BestAnswerByCumulativeScore,
    bca.CumulativeAvgAnswerScore,
    crc.CloseReasonName,
    crc.CloseCount,
    ua.ReputationPerDay,
    ua.ReverseDisplayName
FROM QuestionAnswerLinks qal
LEFT JOIN BestCumulativeAnswer bca ON bca.QuestionId = qal.QuestionId
LEFT JOIN CloseReasonCounts crc ON crc.CloseReasonName IS NOT NULL -- join filtering, all close reasons
LEFT JOIN UserAggregates ua ON ua.Id = qal.QuestionOwner
WHERE qal.QuestionScore >= 5
ORDER BY qal.QuestionScore DESC, qal.FavoriteCount DESC, qal.QuestionCreation ASC
LIMIT 100;