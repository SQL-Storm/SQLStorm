-- {"query": "3284.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1962} 

WITH QuestionStats AS (
    SELECT
        p.Id                                      AS QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.FavoriteCount, 0)               AS Favorites,
        COUNT(a.Id)                                AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(a.CreationDate)                        AS LastAnswerDate,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.Score DESC) AS rn_score
    FROM Posts p
    LEFT JOIN Posts a   ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v   ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY
        p.Id, p.Title, p.Tags, p.CreationDate,
        p.Score, p.ViewCount, p.FavoriteCount
),
TagExploded AS (
    SELECT
        qs.QuestionId,
        qs.Title,
        qs.CreationDate,
        qs.Score,
        qs.ViewCount,
        qs.Favorites,
        qs.AnswerCount,
        qs.UpVotes,
        qs.DownVotes,
        qs.LastAnswerDate,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM qs.Tags), '><')) AS Tag
    FROM QuestionStats qs
),
TagRank AS (
    SELECT
        te.QuestionId,
        te.Tag,
        te.Score,
        ROW_NUMBER() OVER (PARTITION BY te.Tag ORDER BY te.Score DESC) AS TagRank
    FROM TagExploded te
),
UserBadgeAgg AS (
    SELECT
        u.Id                     AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date)               AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
RecentClosed AS (
    SELECT
        p.Id,
        p.Title,
        ph.CreationDate            AS ClosedDate,
        ph.Comment                 AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostHistory ph
      ON ph.PostId = p.Id
     AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1
)
SELECT
    qs.QuestionId,
    qs.Title,
    qs.CreationDate,
    qs.Score,
    qs.ViewCount,
    qs.Favorites,
    qs.AnswerCount,
    qs.UpVotes,
    qs.DownVotes,
    qs.LastAnswerDate,
    rc.ClosedDate,
    rc.CloseReason,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.LastBadgeDate,
    STRING_AGG(DISTINCT tr.Tag || ':' || tr.TagRank::text, ', ') AS TagRanks
FROM QuestionStats qs
LEFT JOIN RecentClosed rc
       ON rc.Id = qs.QuestionId AND rc.rn = 1
LEFT JOIN UserBadgeAgg ub
       ON ub.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = qs.QuestionId)
LEFT JOIN TagRank tr
       ON tr.QuestionId = qs.QuestionId
WHERE qs.rn_score = 1
GROUP BY
    qs.QuestionId, qs.Title, qs.CreationDate, qs.Score, qs.ViewCount,
    qs.Favorites, qs.AnswerCount, qs.UpVotes, qs.DownVotes,
    qs.LastAnswerDate, rc.ClosedDate, rc.CloseReason,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.LastBadgeDate
HAVING COUNT(tr.Tag) > 2
ORDER BY qs.Score DESC
LIMIT 100

UNION ALL

SELECT
    NULL, '--- Separator ---', NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL;
