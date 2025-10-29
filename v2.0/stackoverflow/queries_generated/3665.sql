-- {"query": "3665.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2281} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
        (
            SELECT COUNT(*) 
            FROM Badges b 
            WHERE b.UserId = u.Id AND b.Class = 1
        )                                                             AS GoldBadges,
        (
            SELECT COUNT(*) 
            FROM Badges b 
            WHERE b.UserId = u.Id AND b.Class = 2
        )                                                             AS SilverBadges,
        (
            SELECT COUNT(*) 
            FROM Badges b 
            WHERE b.UserId = u.Id AND b.Class = 3
        )                                                             AS BronzeBadges,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = u.Id
        )                                                             AS TotalPosts,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1
        )                                                             AS Questions,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2
        )                                                             AS Answers,
        (
            SELECT COUNT(*) 
            FROM Votes v 
            WHERE v.UserId = u.Id AND v.VoteTypeId = 2
        )                                                             AS UpVotesGiven,
        (
            SELECT COUNT(*) 
            FROM Votes v 
            WHERE v.UserId = u.Id AND v.VoteTypeId = 3
        )                                                             AS DownVotesGiven
    FROM Users u
    WHERE u.Reputation > 1000
),
Ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, NetVotes DESC)                         AS RepRank,
        RANK() OVER (
            PARTITION BY 
                CASE 
                    WHEN GoldBadges > 0 THEN 'Gold' 
                    WHEN SilverBadges > 0 THEN 'Silver' 
                    ELSE 'Bronze' 
                END 
            ORDER BY Reputation DESC
        )                                                                                  AS TierRank
    FROM UserStats
),
TagAgg AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                                    AS QuestionCount,
        SUM(p.Score)                                   AS TotalScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') 
            FILTER (WHERE u.Id IS NOT NULL)           AS TopContributors
    FROM Tags t
    LEFT JOIN Posts p 
        ON p.Tags LIKE CONCAT('%<', t.TagName, '>%') AND p.PostTypeId = 1
    LEFT JOIN Users u 
        ON u.Id = p.OwnerUserId
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 10
),
RecentActivity AS (
    SELECT
        u.Id,
        MAX(p.CreationDate)                         AS LastPostDate,
        MAX(v.CreationDate)                         AS LastVoteDate,
        GREATEST(
            COALESCE(MAX(p.CreationDate), TIMESTAMP '1970-01-01'), 
            COALESCE(MAX(v.CreationDate), TIMESTAMP '1970-01-01')
        )                                            AS LastActivity
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
),
Combined AS (
    SELECT
        r.Id,
        r.DisplayName,
        r.Reputation,
        r.NetVotes,
        r.GoldBadges,
        r.SilverBadges,
        r.BronzeBadges,
        r.TotalPosts,
        r.Questions,
        r.Answers,
        r.UpVotesGiven,
        r.DownVotesGiven,
        ra.LastActivity,
        CASE 
            WHEN r.RepRank <= 10  THEN 'Top10'
            WHEN r.RepRank <= 100 THEN 'Top100'
            ELSE 'Other'
        END                                          AS RepTier,
        r.RepRank
    FROM Ranked r
    LEFT JOIN RecentActivity ra ON ra.Id = r.Id
)
SELECT
    Id,
    DisplayName,
    Reputation,
    NetVotes,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TotalPosts,
    Questions,
    Answers,
    UpVotesGiven,
    DownVotesGiven,
    LastActivity,
    RepTier,
    RepRank
FROM Combined
WHERE RepTier <> 'Other'

UNION ALL

SELECT
    NULL AS Id,
    'Tag Summary' AS DisplayName,
    NULL AS Reputation,
    NULL AS NetVotes,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS TotalPosts,
    NULL AS Questions,
    NULL AS Answers,
    NULL AS UpVotesGiven,
    NULL AS DownVotesGiven,
    NULL AS LastActivity,
    NULL AS RepTier,
    NULL AS RepRank
FROM (SELECT 1) dummy

EXCEPT

SELECT
    Id,
    DisplayName,
    Reputation,
    NetVotes,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TotalPosts,
    Questions,
    Answers,
    UpVotesGiven,
    DownVotesGiven,
    LastActivity,
    RepTier,
    RepRank
FROM Combined
WHERE RepTier = 'Other'

ORDER BY RepRank ASC NULLS LAST, Reputation DESC;
