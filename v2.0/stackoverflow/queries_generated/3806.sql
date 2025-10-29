-- {"query": "3806.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2301} 

WITH RECURSIVE TagList AS (
    SELECT 
        p.OwnerUserId AS UserId,
        LOWER(TRIM(BOTH '<>' FROM regexp_split_to_table(p.Tags, '><'))) AS Tag
    FROM Posts p
    WHERE p.Tags IS NOT NULL
),
UserTagCounts AS (
    SELECT 
        UserId,
        Tag,
        COUNT(*) AS TagCount
    FROM TagList
    GROUP BY UserId, Tag
),
TopUserTags AS (
    SELECT
        UserId,
        Tag,
        TagCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC, Tag) AS rn
    FROM UserTagCounts
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.CreationDate, '1970-01-01'::timestamp) AS Created,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(p.Score),0) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = u.Id) AS LastVoteDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadgeCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
UserActivityScore AS (
    SELECT 
        us.*,
        (us.QuestionCount * 3 + us.AnswerCount * 5 + us.TotalScore) 
        + (us.GoldBadgeCount * 50 + us.SilverBadgeCount * 20 + us.BronzeBadgeCount * 5) 
        + COALESCE(DATE_PART('day', NOW() - us.LastPostDate),0) * -0.1 AS ActivityScore
    FROM UserStats us
),
RankedUsers AS (
    SELECT 
        uas.*,
        RANK() OVER (ORDER BY uas.ActivityScore DESC) AS ActivityRank,
        ROW_NUMBER() OVER (ORDER BY uas.Reputation DESC) AS ReputationRank
    FROM UserActivityScore uas
),
BadgeUnion AS (
    SELECT 
        b.UserId,
        b.Name AS BadgeName,
        b.Class,
        b.Date,
        'Badge'::text AS Source
    FROM Badges b
    WHERE b.Class = 1
    UNION ALL
    SELECT 
        v.UserId,
        vt.Name AS BadgeName,
        0 AS Class,
        v.CreationDate,
        'Vote'::text AS Source
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.VoteTypeId = 5
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.TotalScore,
    ru.ActivityScore,
    ru.ActivityRank,
    ru.ReputationRank,
    COALESCE(tut.Tag, 'none') AS TopTag,
    COALESCE(tut.TagCount,0) AS TopTagUsage,
    bu.BadgeName,
    bu.Class AS BadgeClass,
    bu.Source,
    CASE 
        WHEN ru.LastPostDate IS NULL THEN 'Never Posted'
        WHEN ru.LastPostDate > NOW() - INTERVAL '30 days' THEN 'Active'
        ELSE 'Dormant'
    END AS RecentPostingStatus,
    CASE 
        WHEN ru.LastVoteDate IS NULL THEN NULL
        ELSE ru.LastVoteDate
    END AS LastVoteDate
FROM RankedUsers ru
LEFT JOIN TopUserTags tut ON tut.UserId = ru.UserId AND tut.rn = 1
LEFT JOIN BadgeUnion bu ON bu.UserId = ru.UserId
WHERE ru.Reputation > 1000
ORDER BY ru.ActivityScore DESC, ru.UserId
LIMIT 100;
