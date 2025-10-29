-- {"query": "3278.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2278} 

WITH
UserPosts AS (
    SELECT
        u.Id                                   AS UserId,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)      AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)      AS AnswerCount,
        SUM(COALESCE(p.Score, 0))                        AS TotalScore,
        MAX(p.CreationDate)                             AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
BadgeAgg AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date)                         AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
TagStats AS (
    SELECT
        u.Id                                 AS UserId,
        STRING_AGG(DISTINCT t.TagName, ',')  AS TagList,
        COUNT(DISTINCT t.Id)                 AS DistinctTagCount
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag
    ) AS pt ON true
    LEFT JOIN Tags t
        ON t.TagName = pt.Tag
    GROUP BY u.Id
),
RecentActivity AS (
    SELECT
        v.UserId,
        MAX(v.CreationDate)                                 AS LastVoteDate,
        COUNT(*) FILTER (WHERE vt.Id = 2)                   AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Id = 3)                   AS DownVotesGiven
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
RankedUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        COALESCE(up.QuestionCount, 0)                         AS Questions,
        COALESCE(up.AnswerCount,   0)                         AS Answers,
        COALESCE(b.GoldBadges,     0)                         AS Gold,
        COALESCE(b.SilverBadges,   0)                         AS Silver,
        COALESCE(b.BronzeBadges,   0)                         AS Bronze,
        COALESCE(ts.DistinctTagCount, 0)                      AS TagCount,
        up.TotalScore,
        up.LastPostDate,
        ROW_NUMBER() OVER (
            ORDER BY (COALESCE(up.TotalScore,0)
                      + COALESCE(b.GoldBadges,0)*100
                      + COALESCE(b.SilverBadges,0)*50) DESC
        )                                                     AS ReputationScore
    FROM Users u
    LEFT JOIN UserPosts   up ON up.UserId   = u.Id
    LEFT JOIN BadgeAgg    b  ON b.UserId    = u.Id
    LEFT JOIN TagStats    ts ON ts.UserId   = u.Id
)
SELECT
    ru.Id,
    ru.DisplayName,
    ru.Questions,
    ru.Answers,
    ru.Gold,
    ru.Silver,
    ru.Bronze,
    ru.TagCount,
    ru.ReputationScore,
    COALESCE(ra.LastVoteDate, ru.LastPostDate)                AS LastActivityDate,
    CASE
        WHEN ru.ReputationScore <= 10   THEN 'Newbie'
        WHEN ru.ReputationScore <= 100  THEN 'Learner'
        WHEN ru.ReputationScore <= 1000 THEN 'Contributor'
        ELSE 'Expert'
    END                                                       AS UserTier,
    ts.TagList
FROM RankedUsers ru
LEFT JOIN RecentActivity ra ON ra.UserId = ru.Id
LEFT JOIN TagStats ts        ON ts.UserId = ru.Id
WHERE ru.ReputationScore > 0

UNION ALL

SELECT
    NULL                                            AS Id,
    '--- Summary ---'                               AS DisplayName,
    SUM(ru.Questions)                               AS Questions,
    SUM(ru.Answers)                                 AS Answers,
    SUM(ru.Gold)                                    AS Gold,
    SUM(ru.Silver)                                  AS Silver,
    SUM(ru.Bronze)                                  AS Bronze,
    NULL                                            AS TagCount,
    NULL                                            AS ReputationScore,
    NULL                                            AS LastActivityDate,
    NULL                                            AS UserTier,
    NULL                                            AS TagList
FROM RankedUsers ru
WHERE ru.ReputationScore > 0

ORDER BY ReputationScore DESC NULLS LAST
LIMIT 100;
