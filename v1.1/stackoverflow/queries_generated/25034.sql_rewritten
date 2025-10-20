-- {"query": "25034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2330} 
WITH TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    WHERE u.Reputation > 10000
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
RecentCloseReasons AS (
    SELECT 
        ph.PostId,
        MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
)
SELECT 
    tu.Id AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.RepRank,
    COALESCE(ubc.GoldBadges,0) AS GoldBadges,
    COALESCE(ubc.SilverBadges,0) AS SilverBadges,
    COALESCE(ubc.BronzeBadges,0) AS BronzeBadges,
    q.Title,
    q.Tags,
    q.Score,
    q.ViewCount,
    COALESCE(rc.CloseReasonId, '0') AS CloseReasonId,
    ROW_NUMBER() OVER (PARTITION BY tu.Id ORDER BY q.CreationDate DESC) AS RecentQuestionRank,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS UpVoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS DownVoteCount,
    COALESCE(NULLIF(q.FavoriteCount,0),0) AS FavoriteCount
FROM TopUsers tu
LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = tu.Id
INNER JOIN Posts q ON q.OwnerUserId = tu.Id AND q.PostTypeId = 1
LEFT JOIN RecentCloseReasons rc ON rc.PostId = q.Id
WHERE 
    (q.Tags LIKE '%<sql>%' OR q.Tags LIKE '%<performance>%')
    AND q.Score >= 0
    AND q.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days')
UNION ALL
SELECT 
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.RepRank,
    COALESCE(ubc.GoldBadges,0),
    COALESCE(ubc.SilverBadges,0),
    COALESCE(ubc.BronzeBadges,0),
    a.Title,
    a.Tags,
    a.Score,
    a.ViewCount,
    NULL AS CloseReasonId,
    ROW_NUMBER() OVER (PARTITION BY tu.Id ORDER BY a.CreationDate DESC) AS RecentAnswerRank,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2) AS UpVoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 3) AS DownVoteCount,
    COALESCE(NULLIF(a.FavoriteCount,0),0) AS FavoriteCount
FROM TopUsers tu
LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = tu.Id
INNER JOIN Posts a ON a.OwnerUserId = tu.Id AND a.PostTypeId = 2
WHERE 
    a.ParentId IS NOT NULL
    AND a.Score > 0
    AND EXISTS (
        SELECT 1 FROM Posts qp
        WHERE qp.Id = a.ParentId
          AND (qp.Tags LIKE '%<sql>%' OR qp.Tags LIKE '%<performance>%')
    )
ORDER BY Reputation DESC, RecentQuestionRank ASC
LIMIT 100;