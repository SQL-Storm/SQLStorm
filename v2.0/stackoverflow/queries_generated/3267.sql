-- {"query": "3267.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2184} 

/*
   Benchmark query combining CTEs, window functions, lateral joins,
   outer joins, correlated subqueries, set operators, complex predicates,
   string handling and NULL logic.
*/

WITH RecentPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),

TagStats AS (
    SELECT
        t.TagName,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score)                                 AS AvgScore
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substring(t.TagName, 2, length(t.TagName)-2), '><')) AS tag
    ) lt ON TRUE
    LEFT JOIN Posts p ON p.Tags LIKE '%' || lt.tag || '%'
    GROUP BY t.TagName
),

UserBadgeAgg AS (
    SELECT
        b.UserId,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)               AS HasGold,
        COUNT(*) FILTER (WHERE b.Class = 2)                        AS SilverCount,
        COUNT(*) FILTER (WHERE b.Class = 3)                        AS BronzeCount,
        STRING_AGG(DISTINCT b.Name, ',')                           AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),

VoteSummary AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod'   THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        MAX(v.CreationDate)                                 AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
)

SELECT
    rp.Id,
    rp.Title,
    rp.Score,
    rp.CreationDate,
    COALESCE(u.DisplayName, 'Anonymous')            AS OwnerDisplayName,
    COALESCE(uba.BadgeList, '')                     AS Badges,
    COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0) AS NetVotes,
    t.TagName,
    ts.QuestionCount,
    ts.AnswerCount,
    ts.AvgScore,
    CASE
        WHEN rp.Score > 10 AND uba.HasGold = 1 THEN 'HotGold'
        WHEN rp.Score > 5                         THEN 'Warm'
        ELSE                                          'Cold'
    END                                            AS HeatLevel,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY rp.Score DESC) AS TagRank
FROM RecentPosts rp
LEFT JOIN Users u          ON rp.OwnerUserId = u.Id
LEFT JOIN UserBadgeAgg uba ON rp.OwnerUserId = uba.UserId
LEFT JOIN VoteSummary vs   ON rp.Id = vs.PostId
LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(rp.Tags, 2, length(rp.Tags)-2), '><')) AS TagName
) t ON TRUE
LEFT JOIN TagStats ts      ON ts.TagName = t.TagName
WHERE rp.rn <= 100
ORDER BY rp.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY

UNION ALL

SELECT
    p.Id,
    p.Title,
    p.Score,
    p.CreationDate,
    COALESCE(p.OwnerDisplayName, 'Deleted') AS OwnerDisplayName,
    ''                                        AS Badges,
    (SELECT COUNT(*) FROM Votes v2
        WHERE v2.PostId = p.Id
          AND v2.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod')) -
    (SELECT COUNT(*) FROM Votes v3
        WHERE v3.PostId = p.Id
          AND v3.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'DownMod')) AS NetVotes,
    NULL                                     AS TagName,
    NULL                                     AS QuestionCount,
    NULL                                     AS AnswerCount,
    NULL                                     AS AvgScore,
    CASE WHEN p.Score > 20 THEN 'SuperHot' ELSE 'Normal' END AS HeatLevel,
    NULL                                     AS TagRank
FROM Posts p
WHERE p.PostTypeId = 1
  AND p.CreationDate < CURRENT_DATE - INTERVAL '30 days'
  AND p.Score > 15
  AND NOT EXISTS (SELECT 1 FROM PostHistory ph
                  WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 12)  -- not deleted
ORDER BY CreationDate DESC
LIMIT 25;
