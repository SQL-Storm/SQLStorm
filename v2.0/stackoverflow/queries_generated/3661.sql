-- {"query": "3661.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1677} 

WITH q_questions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        u.Reputation,
        COALESCE(u.Location, 'Unknown')            AS UserLocation,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_owner
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1                     -- only questions
),

q_tag_stats AS (
    SELECT
        t.TagName,
        COUNT(*)                               AS QuestionCount,
        AVG(p.Score)                           AS AvgScore,
        STRING_AGG(DISTINCT p.Title, '; ') FILTER (WHERE p.Title IS NOT NULL) AS SampleTitles
    FROM Posts p
    JOIN LATERAL regexp_split_to_table(p.Tags, '\><') AS tag(tag) ON TRUE
    JOIN Tags t ON t.TagName = tag.tag
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(*) > 100
),

q_history AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS ReopenedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate END) AS DeletedDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),

q_tags_agg AS (
    SELECT
        p.Id                                    AS PostId,
        STRING_AGG(DISTINCT t.TagName, ',')    AS TagList
    FROM Posts p
    JOIN LATERAL regexp_split_to_table(p.Tags, '\><') AS tag(tag) ON TRUE
    JOIN Tags t ON t.TagName = tag.tag
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
),

q_user_badges AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),

final AS (
    SELECT
        q.Id,
        q.Title,
        q.CreationDate,
        q.Reputation,
        q.UserLocation,
        q.UpVoteCount,
        q.DownVoteCount,
        CASE
            WHEN h.DeletedDate IS NOT NULL                     THEN 'Deleted'
            WHEN h.ClosedDate IS NOT NULL AND h.ReopenedDate IS NULL THEN 'Closed'
            ELSE 'Open'
        END                                            AS Status,
        COALESCE(t.TagList, '')                        AS TagsList,
        COALESCE(b.GoldBadgeCount, 0)                  AS GoldBadges,
        ROW_NUMBER() OVER (ORDER BY (q.UpVoteCount - q.DownVoteCount) DESC) AS RankScore
    FROM q_questions q
    LEFT JOIN q_history h      ON h.PostId = q.Id
    LEFT JOIN q_tags_agg t     ON t.PostId = q.Id
    LEFT JOIN q_user_badges b  ON b.UserId = q.OwnerUserId
    WHERE q.rn_owner = 1
)

SELECT *
FROM final
WHERE Status = 'Open'
UNION ALL
SELECT *
FROM final
WHERE Status = 'Closed' AND RankScore <= 10
ORDER BY Status, RankScore
LIMIT 100;
