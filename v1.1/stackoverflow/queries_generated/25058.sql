-- {"query": "25058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1537} 

WITH RecentPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze
    FROM Badges b
    GROUP BY b.UserId
),
UserAvgScore AS (
    SELECT
        p.OwnerUserId AS UserId,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(bc.Gold, 0)   AS Gold,
        COALESCE(bc.Silver, 0) AS Silver,
        COALESCE(bc.Bronze, 0) AS Bronze,
        COALESCE(avs.AvgAnswerScore, 0) AS AvgAnsScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, Gold DESC, Silver DESC) AS Rank
    FROM Users u
    LEFT JOIN UserBadgeCounts bc  ON u.Id = bc.UserId
    LEFT JOIN UserAvgScore avs    ON u.Id = avs.UserId
    WHERE u.Reputation > 10000
)
SELECT
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.Gold,
    tu.Silver,
    tu.Bronze,
    tu.AvgAnsScore,
    rp.Title,
    rp.Tags,
    rp.Score                               AS RecentScore,
    CASE WHEN pl.LinkTypeId = 3 THEN 'Duplicate' ELSE 'Linked' END AS LinkKind,
    COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0)           AS VoteBalance
FROM TopUsers tu
LEFT JOIN RecentPosts rp
       ON tu.Id = rp.OwnerUserId AND rp.rn = 1
LEFT JOIN PostLinks pl
       ON rp.Id = pl.PostId
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.OwnerUserId
) v
       ON tu.Id = v.OwnerUserId
WHERE tu.Rank <= 100

UNION ALL

SELECT
    NULL AS Id,
    '---' AS DisplayName,
    NULL AS Reputation,
    NULL AS Gold,
    NULL AS Silver,
    NULL AS Bronze,
    NULL AS AvgAnsScore,
    NULL AS Title,
    NULL AS Tags,
    NULL AS RecentScore,
    NULL AS LinkKind,
    NULL AS VoteBalance
FROM (SELECT 1) AS dummy

ORDER BY
    Reputation DESC NULLS LAST,
    Gold DESC,
    Silver DESC
LIMIT 105;
