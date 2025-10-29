-- {"query": "3098.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2114}
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostScore,
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate
    FROM Users u
    WHERE u.Reputation IS NOT NULL
),
TagParticipation AS (
    SELECT 
        pt.OwnerUserId AS UserId,
        -- Use a generic string aggregation function name for wider compatibility:
        -- Some dialects use STRING_AGG(expression, sep), others use GROUP_CONCAT(expression, sep).
        -- Use STRING_AGG here; replace if needed for a specific target.
        STRING_AGG(t.TagName, ', ') AS TagsUsed,
        COUNT(DISTINCT t.Id) AS DistinctTagCount
    FROM Posts pt
    -- split tags stored like "<tag1><tag2>" into rows in a more portable way:
    -- Many engines don't have unnest/string_to_array; emulate using a simple approach when possible.
    -- If your dialect provides a function to split strings to rows, replace the following join accordingly.
    LEFT JOIN (
        SELECT pt_inner.Id AS PostId, TRIM(BOTH '><' FROM pt_inner.Tags) AS TagsRaw
        FROM Posts pt_inner
    ) pt2 ON pt2.PostId = pt.Id
    -- This lateral/unnest emulation will only work if the SQL dialect has a string-split-to-table function.
    -- If not available, replace this join with the appropriate mechanism for your engine.
    LEFT JOIN Tags t ON t.TagName IS NOT NULL AND pt2.TagsRaw LIKE '%' || t.TagName || '%'
    WHERE pt.PostTypeId = 1 AND pt.OwnerUserId IS NOT NULL
    GROUP BY pt.OwnerUserId
),
RecentActivity AS (
    SELECT 
        u.Id,
        -- Replace GREATEST with CASE WHEN for dialects lacking GREATEST; many support GREATEST though.
        -- Use COALESCE to provide defaults, and MAX for joined tables.
        CASE
            WHEN COALESCE(u.LastAccessDate, TIMESTAMP '1970-01-01') >= COALESCE(MAX(c.CreationDate), TIMESTAMP '1970-01-01')
                 AND COALESCE(u.LastAccessDate, TIMESTAMP '1970-01-01') >= COALESCE(MAX(v.CreationDate), TIMESTAMP '1970-01-01')
                THEN COALESCE(u.LastAccessDate, TIMESTAMP '1970-01-01')
            WHEN COALESCE(MAX(c.CreationDate), TIMESTAMP '1970-01-01') >= COALESCE(MAX(v.CreationDate), TIMESTAMP '1970-01-01')
                THEN COALESCE(MAX(c.CreationDate), TIMESTAMP '1970-01-01')
            ELSE COALESCE(MAX(v.CreationDate), TIMESTAMP '1970-01-01')
        END AS LastActivity
    FROM Users u
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes    v ON v.UserId = u.Id
    GROUP BY u.Id, u.LastAccessDate
)
SELECT
    us.Id,
    COALESCE(us.DisplayName, 'Anonymous') || ' (' || us.Id || ')' AS Display,
    us.Reputation,
    us.NetVotes,
    (us.GoldBadges + us.SilverBadges + us.BronzeBadges) AS TotalBadges,
    us.QuestionCount,
    us.AnswerCount,
    ROUND(CAST(us.AvgPostScore AS NUMERIC), 2) AS AvgScore,
    tp.DistinctTagCount,
    tp.TagsUsed,
    ra.LastActivity,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.NetVotes DESC) AS RankByRep,
    CASE
        WHEN us.Reputation >= 20000 THEN 'Legendary'
        WHEN us.Reputation >= 10000 THEN 'Expert'
        WHEN us.Reputation >= 5000  THEN 'Seasoned'
        WHEN us.Reputation >= 1000  THEN 'Intermediate'
        ELSE 'Newbie'
    END AS ReputationTier,
    (SELECT COUNT(*) FROM Posts p
        WHERE p.OwnerUserId = us.Id
          AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
          AND p.PostTypeId = 2) AS AnswersLast30Days,
    (SELECT COUNT(*) FROM Votes v
        WHERE v.UserId = us.Id
          AND v.VoteTypeId = 2
          AND v.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '7' DAY) AS UpVotesLastWeek
FROM UserStats us
LEFT JOIN TagParticipation tp ON tp.UserId = us.Id
LEFT JOIN RecentActivity   ra ON ra.Id = us.Id
WHERE us.Reputation > 0

UNION ALL

SELECT
    -1                                        AS Id,
    'Community'                               AS Display,
    NULL                                      AS Reputation,
    NULL                                      AS NetVotes,
    NULL                                      AS TotalBadges,
    NULL                                      AS QuestionCount,
    NULL                                      AS AnswerCount,
    NULL                                      AS AvgScore,
    NULL                                      AS DistinctTagCount,
    NULL                                      AS TagsUsed,
    NULL                                      AS LastActivity,
    NULL                                      AS RankByRep,
    NULL                                      AS ReputationTier,
    NULL                                      AS AnswersLast30Days,
    NULL                                      AS UpVotesLastWeek

ORDER BY RankByRep
LIMIT 100;