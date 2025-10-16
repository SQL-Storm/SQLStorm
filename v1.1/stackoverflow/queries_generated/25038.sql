-- {"query": "25038.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2345} 

WITH UserPostStats AS (
    SELECT 
        u.Id                              AS UserId,
        u.DisplayName,
        p.Id                              AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.Title,
        COALESCE(p.Tags, '')              AS Tags,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS rn,
        AVG(p.Score) OVER (
            PARTITION BY u.Id 
            ORDER BY p.CreationDate 
            ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
        )                                 AS AvgScoreLast5
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)        -- questions & answers
),
TopPosts AS (
    SELECT *
    FROM UserPostStats
    WHERE rn <= 10                      -- top‑10 recent posts per user
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*)                                   AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteAgg AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
TagExtraction AS (
    SELECT 
        p.Id                         AS PostId,
        UNNEST(string_to_array(
            substring(p.Tags, 2, length(p.Tags)-2), 
            '><'
        ))                           AS Tag
    FROM Posts p
    WHERE p.Tags IS NOT NULL 
      AND p.Tags <> ''
),
TagStats AS (
    SELECT 
        te.Tag,
        COUNT(DISTINCT te.PostId)    AS PostCount,
        SUM(p.Score)                 AS TotalScore,
        AVG(p.Score)                 AS AvgScore
    FROM TagExtraction te
    JOIN Posts p ON p.Id = te.PostId
    GROUP BY te.Tag
),
Combined AS (
    SELECT 
        tp.UserId,
        tp.PostId,
        tp.Title,
        tp.Score,
        tp.AvgScoreLast5,
        COALESCE(uv.UpVotes, 0)      AS UpVotes,
        COALESCE(uv.DownVotes, 0)    AS DownVotes,
        COALESCE(ub.GoldBadges, 0)   AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        CASE WHEN tp.Score >= 0 THEN 'Positive' ELSE 'Negative' END AS ScoreSign,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM PostHistory ph 
                WHERE ph.PostId = tp.PostId 
                  AND ph.PostHistoryTypeId = 10
            ) THEN 1 ELSE 0 
        END                         AS WasClosed
    FROM TopPosts tp
    LEFT JOIN UserVoteAgg uv ON uv.PostId = tp.PostId
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = tp.UserId
)
SELECT 
    c.UserId,
    u.DisplayName,
    c.PostId,
    c.Title,
    c.Score,
    c.AvgScoreLast5,
    c.UpVotes,
    c.DownVotes,
    c.GoldBadges,
    c.SilverBadges,
    c.BronzeBadges,
    c.ScoreSign,
    c.WasClosed,
    ts.Tag,
    ts.PostCount,
    ts.TotalScore,
    ts.AvgScore
FROM Combined c
JOIN Users u ON u.Id = c.UserId
LEFT JOIN LATERAL (
    SELECT 
        te.Tag,
        ts.PostCount,
        ts.TotalScore,
        ts.AvgScore
    FROM TagExtraction te
    JOIN TagStats ts ON ts.Tag = te.Tag
    WHERE te.PostId = c.PostId
    ORDER BY ts.TotalScore DESC
    LIMIT 1
) ts ON true
WHERE c.ScoreSign = 'Positive'

UNION ALL

SELECT 
    NULL                 AS UserId,
    'Aggregated Tag Summary' AS DisplayName,
    NULL                 AS PostId,
    NULL                 AS Title,
    NULL                 AS Score,
    NULL                 AS AvgScoreLast5,
    NULL                 AS UpVotes,
    NULL                 AS DownVotes,
    NULL                 AS GoldBadges,
    NULL                 AS SilverBadges,
    NULL                 AS BronzeBadges,
    NULL                 AS ScoreSign,
    NULL                 AS WasClosed,
    t.Tag,
    t.PostCount,
    t.TotalScore,
    t.AvgScore
FROM TagStats t
WHERE t.PostCount > 1000
ORDER BY GoldBadges DESC NULLS LAST, TotalScore DESC NULLS LAST
LIMIT 200;
