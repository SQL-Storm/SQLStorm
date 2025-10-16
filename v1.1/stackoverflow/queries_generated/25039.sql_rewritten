-- {"query": "25039.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1921} 
WITH RecentBadges AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    WHERE b.Date >= cast('2024-10-01' as date) - INTERVAL '90 days'
    GROUP BY b.UserId
),
UserPostStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(
            DISTINCT COALESCE(NULLIF(trim(both '<>' FROM split_part(p.Tags, '><', 1)), ''), ''),
            ','
        ) AS FirstTagList
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(rb.GoldBadges, 0)      AS GoldBadges,
        COALESCE(rb.SilverBadges, 0)    AS SilverBadges,
        COALESCE(rb.BronzeBadges, 0)    AS BronzeBadges,
        COALESCE(ups.QuestionCount, 0)  AS Questions,
        COALESCE(ups.AnswerCount, 0)    AS Answers,
        ROUND(COALESCE(ups.AvgAnswerScore, 0), 2) AS AvgAnsScore,
        COALESCE(ups.FirstTagList, '(none)')     AS TagsSample,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(rb.GoldBadges,0) DESC) AS RankByRep,
        (
            SELECT MAX(v.CreationDate)
            FROM Votes v
            JOIN Posts p ON p.Id = v.PostId
            WHERE p.OwnerUserId = u.Id
        ) AS LastVoteDate
    FROM Users u
    LEFT JOIN RecentBadges rb ON rb.UserId = u.Id               -- outer join
    LEFT JOIN UserPostStats ups ON ups.UserId = u.Id
)
SELECT *
FROM TopUsers
WHERE RankByRep <= 100

UNION ALL

SELECT
    t2.Id,
    t2.DisplayName,
    t2.Reputation,
    t2.GoldBadges,
    t2.SilverBadges,
    t2.BronzeBadges,
    NULL AS Questions,
    NULL AS Answers,
    NULL AS AvgAnsScore,
    NULL AS TagsSample,
    NULL AS RankByRep,
    NULL AS LastVoteDate
FROM (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(rb.GoldBadges, 0) AS GoldBadges,
        COALESCE(rb.SilverBadges, 0) AS SilverBadges,
        COALESCE(rb.BronzeBadges, 0) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY COALESCE(rb.GoldBadges,0) DESC, u.Reputation DESC) AS RankByGold
    FROM Users u
    LEFT JOIN RecentBadges rb ON rb.UserId = u.Id               -- outer join
    WHERE COALESCE(rb.GoldBadges,0) > 0
) t2
WHERE t2.RankByGold <= 50
ORDER BY Reputation DESC, GoldBadges DESC, RankByRep ASC;