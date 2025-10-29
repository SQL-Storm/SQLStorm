-- {"query": "3101.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2724} 

WITH
    UserBadgeCounts AS (
        SELECT
            u.Id                                 AS UserId,
            u.DisplayName,
            COUNT(*) FILTER (WHERE b.Class = 1)  AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2)  AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3)  AS BronzeBadges,
            SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBasedBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName
    ),

    RecentQuestionActivity AS (
        SELECT
            p.Id                                   AS QuestionId,
            p.Title,
            p.CreationDate,
            COALESCE(p.Score, 0)                   AS QuestionScore,
            COALESCE(p.ViewCount, 0)               AS Views,
            COALESCE(p.FavoriteCount, 0)           AS Favorites,
            (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount,
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id)                      AS CommentCount,
            ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC)                            AS RecentRank
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    ),

    TagCooccurrence AS (
        SELECT
            t1.tag   AS TagA,
            t2.tag   AS TagB,
            COUNT(*) AS CooccurCount
        FROM Posts p
        CROSS JOIN LATERAL regexp_split_to_table(p.Tags, '[><]') AS t1(tag)
        CROSS JOIN LATERAL regexp_split_to_table(p.Tags, '[><]') AS t2(tag)
        WHERE p.PostTypeId = 1
          AND t1.tag <> '' AND t2.tag <> ''
          AND t1.tag < t2.tag                     -- avoid duplicates / self‑joins
        GROUP BY t1.tag, t2.tag
        HAVING COUNT(*) > 10
    ),

    VoteAggregates AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
            MAX(v.CreationDate)                               AS LastVoteDate
        FROM Votes v
        GROUP BY v.PostId
    ),

    ClosedReasons AS (
        SELECT
            ph.PostId,
            MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReasonId
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
        GROUP BY ph.PostId
    )

SELECT
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.QuestionScore,
    rq.Views,
    rq.Favorites,
    rq.AnswerCount,
    rq.CommentCount,
    COALESCE(va.UpVotes, 0)   AS TotalUpVotes,
    COALESCE(va.DownVotes, 0) AS TotalDownVotes,
    cr.CloseReasonId,
    ub.DisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadges,
    CASE
        WHEN rq.QuestionScore + COALESCE(va.UpVotes,0) - COALESCE(va.DownVotes,0) > 100 THEN 'Hot'
        WHEN rq.Views > 1000                                                       THEN 'Popular'
        ELSE 'Normal'
    END AS ActivityTier,
    STRING_AGG(DISTINCT t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL)          AS TagsList,
    STRING_AGG(DISTINCT tc.TagB, ', ')   FILTER (WHERE tc.CooccurCount > 20)          AS RelatedTags
FROM RecentQuestionActivity rq
LEFT JOIN VoteAggregates      va ON va.PostId = rq.QuestionId
LEFT JOIN ClosedReasons       cr ON cr.PostId = rq.QuestionId
LEFT JOIN Users               u  ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = rq.QuestionId)
LEFT JOIN UserBadgeCounts    ub  ON ub.UserId = u.Id
LEFT JOIN LATERAL (
        SELECT regexp_split_to_table(p.Tags, '[><]') AS TagName
        FROM Posts p
        WHERE p.Id = rq.QuestionId
    ) t ON TRUE
LEFT JOIN TagCooccurrence tc ON tc.TagA = ANY (ARRAY[ t.TagName ])
WHERE ub.GoldBadges > 0 OR ub.SilverBadges > 0
GROUP BY
    rq.QuestionId, rq.Title, rq.CreationDate, rq.QuestionScore, rq.Views,
    rq.Favorites, rq.AnswerCount, rq.CommentCount,
    va.UpVotes, va.DownVotes, cr.CloseReasonId,
    ub.DisplayName, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TagBasedBadges

UNION ALL

SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.FavoriteCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2),
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id),
    COALESCE(vu.UpVotes, 0),
    COALESCE(vu.DownVotes, 0),
    NULL,
    u.DisplayName,
    0, 0, 0, 0,
    'Legacy',
    NULL,
    NULL
FROM Posts p
LEFT JOIN VoteAggregates vu ON vu.PostId = p.Id
LEFT JOIN Users u          ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
  AND p.CreationDate < CURRENT_DATE - INTERVAL '365 days'
  AND (p.Score IS NULL OR p.Score < 0)

ORDER BY QuestionId DESC
LIMIT 100;
