-- {"query": "3962.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1981} 
WITH UserBadgeCounts AS (
    SELECT 
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
    FROM Badges
    GROUP BY UserId
),
RecentQuestions AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ub.GoldCount,
        ub.SilverCount,
        ub.BronzeCount,
        rq.Id AS RecentQuestionId,
        rq.Score AS RecentScore,
        (
            SELECT t.TagName
            FROM Posts p2
            CROSS JOIN LATERAL string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><') AS t(tag)
            JOIN Tags t ON t.TagName = t.tag
            WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1
            GROUP BY t.TagName
            ORDER BY COUNT(*) DESC
            LIMIT 1
        ) AS MostUsedTag
    FROM Users u
    LEFT JOIN UserBadgeCounts ub ON u.Id = ub.UserId
    LEFT JOIN RecentQuestions rq ON u.Id = rq.OwnerUserId AND rq.rn = 1
),
CommentAgg AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS CommentCount
    FROM Comments c
    JOIN Posts p ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
VoteAgg AS (
    SELECT 
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
Combined AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        COALESCE(us.GoldCount, 0) AS GoldBadges,
        COALESCE(us.SilverCount, 0) AS SilverBadges,
        COALESCE(us.BronzeCount, 0) AS BronzeBadges,
        us.RecentQuestionId,
        us.RecentScore,
        us.MostUsedTag,
        COALESCE(ca.CommentCount, 0) AS TotalCommentsOnQuestions,
        COALESCE(va.UpVotes, 0) AS TotalUpVotes,
        COALESCE(va.DownVotes, 0) AS TotalDownVotes,
        (us.Reputation * (COALESCE(us.GoldCount, 0) + 0.5 * COALESCE(us.SilverCount, 0))) AS WeightedScore
    FROM UserStats us
    LEFT JOIN CommentAgg ca ON us.UserId = ca.OwnerUserId
    LEFT JOIN VoteAgg va ON us.UserId = va.OwnerUserId
),
Ranked AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY WeightedScore DESC) AS Rank
    FROM Combined
    WHERE Reputation > 1000
)
SELECT 
    Rank,
    UserId,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    RecentQuestionId,
    RecentScore,
    MostUsedTag,
    TotalCommentsOnQuestions,
    TotalUpVotes,
    TotalDownVotes,
    WeightedScore
FROM Ranked
WHERE Rank <= 100

UNION ALL

SELECT 
    NULL, NULL, '---', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
ORDER BY 
    Rank ASC NULLS FIRST;