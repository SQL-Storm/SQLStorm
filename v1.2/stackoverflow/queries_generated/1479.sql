-- {"query": "1479.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1506} 

WITH RecursiveTagCTE AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        p.Id AS ExcerptPostId,
        p.Title AS ExcerptTitle,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS RankByCount
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
    WHERE t.Count > 5000
    UNION ALL
    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        p2.Id,
        p2.Title,
        rt.RankByCount + 1000
    FROM Tags t2
    INNER JOIN RecursiveTagCTE rt ON rt.Id <> t2.Id AND t2.Count > rt.Count / 10
    LEFT JOIN Posts p2 ON p2.Id = t2.ExcerptPostId
    WHERE t2.Count BETWEEN rt.Count / 10 AND rt.Count / 5
),
UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(b.Class) AS HighestBadgeClass,
        COALESCE(AVG(vtScore.VoteWeight), 0) AS AvgVoteWeightPerPost,
        FIRST_VALUE(p1.Title) OVER (PARTITION BY u.Id ORDER BY p1.Score DESC NULLS LAST) AS TopScoringQuestionTitle,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Class <= 2
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN LATERAL (
        SELECT v.VoteTypeId,
        CASE
            WHEN v.VoteTypeId = 2 THEN 1
            WHEN v.VoteTypeId = 3 THEN -1
            ELSE 0
        END AS VoteWeight
        FROM Votes v
        WHERE v.PostId = p.Id
    ) vtScore ON true
    LEFT JOIN Posts p1 ON p1.OwnerUserId = u.Id AND p1.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId IN (1, 2)) > 10
),
TopPostsByScore AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.CreationDate,
        u.DisplayName,
        (p.Score * COALESCE(LENGTH(p.Body) / 4048.0, 1)) AS AdjustedPostScore,
        dense_rank() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
),
PostLinkSummary AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS DuplicateLinks,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Linked' THEN pl.RelatedPostId END) AS OutgoingLinks,
        MAX(pl.CreationDate) AS LastLinkDate
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId
),
UserEngagementSummary AS (
    SELECT
        ua.Id as UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.BadgeCount,
        ua.HighestBadgeClass,
        ua.AvgVoteWeightPerPost,
        ua.CommentCount,
        tp.ScoreRank,
        pll.DuplicateLinks,
        pll.OutgoingLinks,
        pll.LastLinkDate,
        CASE
            WHEN ua.QuestionCount = 0 THEN NULL
            ELSE ua.AnswerCount::decimal / ua.QuestionCount
        END AS AnswerToQuestionRatio,
        CASE                
            WHEN pll.DuplicateLinks > 5 THEN 'Highly Linked Duplicate Prone'
            WHEN pll.OutgoingLinks > 20 THEN 'Well Connected Posts'
            ELSE 'Regular'
        END AS PostConnectivityType,
        ConcatenatedTags.TagsAggregate
    FROM UserActivity ua
    LEFT JOIN TopPostsByScore tp ON tp.Id = (
        SELECT Id FROM Posts p WHERE p.OwnerUserId = ua.Id ORDER BY p.Score DESC NULLS LAST LIMIT 1
    )
    LEFT JOIN PostLinkSummary pll ON pll.PostId = tp.Id
    LEFT JOIN (
        SELECT 
            OwnerUserId,
            STRING_AGG(DISTINCT TRIM(BOTH '<>?' FROM unnest(string_to_array(substring(Tags, 2, length(Tags) - 2), '><'))), ', ' ORDER BY NULL) AS TagsAggregate
        FROM Posts
        WHERE OwnerUserId IS NOT NULL AND Tags IS NOT NULL
        GROUP BY OwnerUserId
    ) ConcatenatedTags ON ConcatenatedTags.OwnerUserId = ua.Id
    WHERE ua.Reputation > 1000
)
SELECT
    ues.DisplayName,
    ues.Reputation,
    ues.QuestionCount,
    ues.AnswerCount,
    ues.AverageLikeRate,
    ues.BadgeCount,
    ues.HighestBadgeClass,
    ues.AvgVoteWeightPerPost,
    ues.CommentCount,
    ues.ScoreRank,
    ues.DuplicateLinks,
    ues.OutgoingLinks,
    ues.PostConnectivityType,
    COALESCE(ues.TagsAggregate, 'No Tags Found') AS TopTags,
    recursiveTagsRanks.TagName AS MostRelevantTag,
    recursiveTagsRanks.Count AS TagUseFrequency,
    nt.DurationSinceCreationDays,
    nt.HourOfLastEdit,
    CONCAT('Question: "', tpbps.Title, '" (Score: ', tpbps.Score, ')') AS TopQuestionInfo
FROM UserEngagementSummary ues
LEFT JOIN RecursiveTagCTE recursiveTagsRanks ON recursiveTagsRanks.RankByCount = 
    (SELECT MIN(RankByCount) FROM RecursiveTagCTE)
LEFT JOIN TopPostsByScore tpbps ON tpbps.Id = (
    SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ues.UserId AND p.PostTypeId = 1 ORDER BY p.Score DESC LIMIT 1
)
LEFT JOIN LATERAL (
    SELECT 
        date_part('day', now() - p.CreationDate) AS DurationSinceCreationDays,
        date_part('hour', p.LastEditDate) AS HourOfLastEdit
    FROM Posts p
    WHERE p.OwnerUserId = ues.UserId
    ORDER BY p.LastEditDate DESC LIMIT 1
) nt ON true
ORDER BY ues.Reputation DESC, ues.BadgeCount DESC, ues.HighestBadgeClass ASC
LIMIT 50;
