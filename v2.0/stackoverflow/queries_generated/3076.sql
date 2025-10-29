-- {"query": "3076.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2595} 

WITH
    RepRank AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS RepDenseRank
        FROM Users u
    ),
    BadgeAgg AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 3
                     WHEN b.Class = 2 THEN 2
                     ELSE 1 END) AS BadgeScore,
            COUNT(*) FILTER (WHERE b.TagBased = 1) AS TagBadgeCount,
            COUNT(*) FILTER (WHERE b.TagBased = 0) AS NamedBadgeCount
        FROM Badges b
        GROUP BY b.UserId
    ),
    VoteAgg AS (
        SELECT
            v.UserId,
            COUNT(*) FILTER (WHERE vt.Id = 2) AS UpVotesGiven,
            COUNT(*) FILTER (WHERE vt.Id = 3) AS DownVotesGiven,
            COUNT(*) FILTER (WHERE vt.Id = 1) AS AcceptedVotes,
            SUM(CASE WHEN vt.Id = 8 THEN v.BountyAmount ELSE 0 END) AS BountyStarted,
            SUM(CASE WHEN vt.Id = 9 THEN v.BountyAmount ELSE 0 END) AS BountyAwarded
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE v.UserId IS NOT NULL
        GROUP BY v.UserId
    ),
    RecentPosts AS (
        SELECT
            p.OwnerUserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1 AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days') AS RecentQuestions,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2 AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days') AS RecentAnswers,
            MAX(p.CreationDate) AS LastPostDate
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    UserTagStats AS (
        SELECT
            u.Id AS UserId,
            STRING_AGG(t.TagName, ',') FILTER (WHERE t.TagName IS NOT NULL) AS TagsUsed,
            COUNT(DISTINCT t.TagName) AS DistinctTagCount
        FROM Users u
        JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
        LEFT JOIN LATERAL (
            SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag
        ) AS pt ON TRUE
        LEFT JOIN Tags t ON t.TagName = pt.Tag
        GROUP BY u.Id
    )
SELECT
    r.Id,
    r.DisplayName,
    r.Reputation,
    r.RepDenseRank,
    COALESCE(b.BadgeScore,0)           AS BadgeScore,
    COALESCE(b.TagBadgeCount,0)        AS TagBadgeCount,
    COALESCE(b.NamedBadgeCount,0)      AS NamedBadgeCount,
    COALESCE(v.UpVotesGiven,0)         AS UpVotesGiven,
    COALESCE(v.DownVotesGiven,0)       AS DownVotesGiven,
    COALESCE(v.AcceptedVotes,0)        AS AcceptedVotes,
    COALESCE(v.BountyStarted,0)        AS BountyStarted,
    COALESCE(v.BountyAwarded,0)        AS BountyAwarded,
    COALESCE(rp.RecentQuestions,0)     AS RecentQuestions,
    COALESCE(rp.RecentAnswers,0)       AS RecentAnswers,
    rp.LastPostDate,
    COALESCE(t.TagsUsed,'')            AS TagsUsed,
    COALESCE(t.DistinctTagCount,0)     AS DistinctTagCount,
    ROW_NUMBER() OVER (ORDER BY r.Reputation DESC, COALESCE(b.BadgeScore,0) DESC) AS OverallRank,
    CASE
        WHEN r.Reputation > 200000 THEN 'Legendary'
        WHEN r.Reputation > 100000 THEN 'Guru'
        WHEN r.Reputation > 50000  THEN 'Expert'
        WHEN r.Reputation > 10000  THEN 'Enthusiast'
        ELSE 'Member'
    END                               AS ReputationTier,
    CASE
        WHEN r.Location IS NULL AND r.AboutMe IS NOT NULL THEN 'Anonymous'
        WHEN r.Location IS NOT NULL AND POSITION('United' IN r.Location) > 0 THEN 'US Resident'
        ELSE 'Global'
    END                               AS GeoCategory
FROM RepRank r
LEFT JOIN BadgeAgg   b ON b.UserId = r.Id
LEFT JOIN VoteAgg    v ON v.UserId = r.Id
LEFT JOIN RecentPosts rp ON rp.OwnerUserId = r.Id
LEFT JOIN UserTagStats t ON t.UserId = r.Id
WHERE r.RepDenseRank <= 1000
   OR (b.BadgeScore IS NOT NULL AND b.BadgeScore > 50)

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    NULL,
    0,0,0,
    0,0,0,0,0,
    0,0,NULL,
    '' ,0,
    NULL,
    NULL,
    NULL
FROM Users u
WHERE u.CreationDate > CURRENT_DATE - INTERVAL '7 days'
  AND u.Reputation IS NOT NULL

ORDER BY OverallRank NULLS LAST, Reputation DESC;
