-- {"query": "3289.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3527}
WITH
UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgeCount,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadgeCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId = 1), 0) AS QuestionScoreSum,
        COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId = 2), 0) AS AnswerScoreSum,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, GoldBadgeCount DESC) AS rn
    FROM UserStats
    WHERE Reputation > 5000
),
UserTagInfo AS (
    SELECT
        u.Id,
        COUNT(DISTINCT t.tag) AS DistinctTagCount,
        STRING_AGG(DISTINCT t.tag, ';') AS TagList
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.Tags IS NOT NULL
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
    ) t ON TRUE
    GROUP BY u.Id
),
TagStats AS (
    SELECT
        t.TagName,
        t.Count AS TagUseCount,
        COUNT(DISTINCT p.Id) AS PostsWithTag,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEvents
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT p.Id, p.Tags
        FROM Posts p
        WHERE p.Tags IS NOT NULL
    ) p ON p.Tags ILIKE '%' || t.TagName || '%'
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    GROUP BY t.TagName, t.Count
),
RecentVoteAgg AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS UpVotes30d,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotes30d,
        MAX(v.CreationDate)                         AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    GROUP BY v.UserId
),
TopTagPerUser AS (
    SELECT
        tu.Id AS UserId,
        ts.TagName,
        ts.TagUseCount,
        ts.PostsWithTag,
        ts.CloseEvents,
        ROW_NUMBER() OVER (PARTITION BY tu.Id ORDER BY ts.TagUseCount DESC) AS tag_rn
    FROM TopUsers tu
    LEFT JOIN LATERAL (
        SELECT *
        FROM TagStats ts
        ORDER BY ts.TagUseCount DESC
        LIMIT 5
    ) ts ON TRUE
)
SELECT
    tu.rn,
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadgeCount,
    tu.SilverBadgeCount,
    tu.QuestionCount,
    tu.AnswerCount,
    ROUND(
        CASE WHEN tu.QuestionCount = 0 THEN NULL
        ELSE CAST(tu.QuestionScoreSum AS numeric) / tu.QuestionCount END, 2
    ) AS AvgQuestionScore,
    tu.LastPostDate,
    COALESCE(rv.UpVotes30d, 0)   AS UpVotesLast30d,
    COALESCE(rv.DownVotes30d, 0) AS DownVotesLast30d,
    COALESCE(uti.DistinctTagCount, 0) AS DistinctTagsUsed,
    COALESCE(uti.TagList, '')          AS TagList,
    tp.TagName,
    tp.TagUseCount,
    tp.PostsWithTag,
    tp.CloseEvents
FROM TopUsers tu
LEFT JOIN RecentVoteAgg rv   ON rv.UserId = tu.Id
LEFT JOIN UserTagInfo uti    ON uti.Id = tu.Id
LEFT JOIN TopTagPerUser tp  ON tp.UserId = tu.Id AND tp.tag_rn = 1
WHERE tu.rn <= 100
UNION ALL
SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE NOT EXISTS (SELECT 1 FROM TopUsers WHERE rn <= 100);