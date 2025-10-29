-- {"query": "3817.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2336}
WITH TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM Users u
    WHERE u.Reputation > 1000
),
UserPostStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    GROUP BY p.OwnerUserId
),
BadgesAgg AS (
    SELECT 
        b.UserId,
        COUNT(*) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagUse AS (
    SELECT 
        tag,
        COUNT(*) AS TagUseCount
    FROM (
        SELECT 
            UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) sub
    GROUP BY tag
),
UserTopTag AS (
    SELECT 
        p.OwnerUserId,
        pt.tag,
        t.TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY t.TagUseCount DESC) AS rn
    FROM Posts p
    JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
    ) pt ON TRUE
    JOIN TagUse t ON t.tag = pt.tag
    WHERE p.PostTypeId = 1
),
UserVotes AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven
    FROM Votes v
    GROUP BY v.UserId
)

SELECT 
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    COALESCE(NULLIF(tu.Location, ''), 'Unknown') AS Location,
    COALESCE(ups.QuestionCount, 0) AS QuestionsPosted,
    COALESCE(ups.AnswerCount, 0) AS AnswersPosted,
    COALESCE(ups.TotalScore, 0) AS AggregateScore,
    ups.LastPostDate,
    COALESCE(bag.BadgeCount, 0) AS TotalBadges,
    COALESCE(bag.GoldBadges, 0) AS GoldBadges,
    COALESCE(bag.SilverBadges, 0) AS SilverBadges,
    COALESCE(bag.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(vu.UpVotesGiven, 0) AS UpVotesCast,
    COALESCE(vu.DownVotesGiven, 0) AS DownVotesCast,
    (SELECT AVG(a.Score)
     FROM Posts q
     JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
     WHERE q.OwnerUserId = tu.Id AND q.PostTypeId = 1) AS AvgAnswerScore,
    ut.tag AS TopTag,
    ut.TagUseCount AS TopTagUsage
FROM TopUsers tu
LEFT JOIN UserPostStats ups      ON ups.UserId = tu.Id
LEFT JOIN BadgesAgg bag         ON bag.UserId = tu.Id
LEFT JOIN UserVotes vu          ON vu.UserId = tu.Id
LEFT JOIN UserTopTag ut         ON ut.OwnerUserId = tu.Id AND ut.rn = 1
WHERE tu.rn <= 100

UNION ALL

SELECT 
    NULL AS Id,
    'TOTAL SUMMARY' AS DisplayName,
    NULL AS Reputation,
    NULL AS Location,
    SUM(COALESCE(ups.QuestionCount,0))      AS QuestionsPosted,
    SUM(COALESCE(ups.AnswerCount,0))        AS AnswersPosted,
    SUM(COALESCE(ups.TotalScore,0))         AS AggregateScore,
    MAX(ups.LastPostDate)                  AS LastPostDate,
    SUM(COALESCE(bag.BadgeCount,0))         AS TotalBadges,
    SUM(COALESCE(bag.GoldBadges,0))         AS GoldBadges,
    SUM(COALESCE(bag.SilverBadges,0))       AS SilverBadges,
    SUM(COALESCE(bag.BronzeBadges,0))       AS BronzeBadges,
    SUM(COALESCE(vu.UpVotesGiven,0))        AS UpVotesCast,
    SUM(COALESCE(vu.DownVotesGiven,0))      AS DownVotesCast,
    NULL                                    AS AvgAnswerScore,
    NULL                                    AS TopTag,
    NULL                                    AS TopTagUsage
FROM TopUsers tu
LEFT JOIN UserPostStats ups ON ups.UserId = tu.Id
LEFT JOIN BadgesAgg bag    ON bag.UserId = tu.Id
LEFT JOIN UserVotes vu    ON vu.UserId = tu.Id
WHERE tu.rn <= 100

ORDER BY Reputation DESC NULLS LAST
LIMIT 150;