-- {"query": "3281.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2375} 

/*  PERFORMANCE BENCHMARK QUERY – uses CTEs, window functions, outer joins, 
    correlated subqueries, LATERAL, string ops, NULL logic and a set operator   */

WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
           COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1)             AS GoldBadges,
           COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2)             AS SilverBadges,
           COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3)             AS BronzeBadges,
           MAX(p.CreationDate)                                         AS LastPostDate,
           MAX(v.CreationDate)                                         AS LastVoteDate
    FROM   Users  u
    LEFT  JOIN Badges b   ON b.UserId = u.Id
    LEFT  JOIN Posts  p   ON p.OwnerUserId = u.Id
    LEFT  JOIN Votes  v   ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),

TagStats AS (
    SELECT t.TagName,
           COUNT(p.Id)                                                    AS TaggedPostCount,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)                  AS AvgQuestionScore,
           AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)                  AS AvgAnswerScore
    FROM   Tags   t
    JOIN   Posts  p ON p.Tags LIKE '%'||t.TagName||'%'
    WHERE  p.PostTypeId IN (1,2)
    GROUP BY t.TagName
),

RecentActivity AS (
    SELECT u.Id,
           GREATEST(
               COALESCE(us.LastPostDate, TIMESTAMP '1970-01-01'),
               COALESCE(us.LastVoteDate, TIMESTAMP '1970-01-01'),
               COALESCE(le.LastEditDate, TIMESTAMP '1970-01-01')
           )                                                          AS RecentDate
    FROM   Users u
    JOIN   UserStats us      ON us.Id = u.Id
    LEFT  JOIN LATERAL (
               SELECT MAX(LastEditDate) AS LastEditDate
               FROM   Posts p
               WHERE  p.OwnerUserId = u.Id
           ) le ON TRUE
),

RankedUsers AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY Reputation DESC, NetVotes DESC) AS ReputationRank,
           RANK()      OVER (ORDER BY GoldBadges DESC)               AS GoldBadgeRank
    FROM   UserStats
)

SELECT  ru.Id,
        ru.DisplayName,
        ru.Reputation,
        ru.NetVotes,
        ru.GoldBadges,
        ru.SilverBadges,
        ru.BronzeBadges,
        ru.ReputationRank,
        ru.GoldBadgeRank,
        ra.RecentDate,
        STRING_AGG(t.TagName, ', ') 
            FILTER (WHERE t.TagName IS NOT NULL)                     AS TopTags,
        CASE 
            WHEN ru.GoldBadges > 0 THEN 'Elite'
            WHEN ru.SilverBadges > 0 THEN 'Pro'
            ELSE 'Member'
        END                                                       AS MemberLevel
FROM    RankedUsers      ru
JOIN    RecentActivity   ra ON ra.Id = ru.Id
LEFT   JOIN Posts p ON p.OwnerUserId = ru.Id AND p.PostTypeId = 1
LEFT   JOIN LATERAL (
          SELECT UNNEST(string_to_array(
                 TRIM(BOTH '<>' FROM p.Tags), '><')) AS TagName
       ) pt ON TRUE
LEFT   JOIN TagStats t ON t.TagName = pt.TagName
WHERE   ru.Reputation >= 1000
  AND   (ru.GoldBadges + ru.SilverBadges + ru.BronzeBadges) > 0
  AND   ra.RecentDate > CURRENT_DATE - INTERVAL '180 days'
GROUP BY ru.Id, ru.DisplayName, ru.Reputation, ru.NetVotes,
         ru.GoldBadges, ru.SilverBadges, ru.BronzeBadges,
         ru.ReputationRank, ru.GoldBadgeRank, ra.RecentDate
HAVING COUNT(t.TagName) > 0

UNION ALL

SELECT  NULL                                      AS Id,
        'Summary'                                 AS DisplayName,
        SUM(ru.Reputation)                        AS Reputation,
        SUM(ru.NetVotes)                          AS NetVotes,
        SUM(ru.GoldBadges)                        AS GoldBadges,
        SUM(ru.SilverBadges)                      AS SilverBadges,
        SUM(ru.BronzeBadges)                      AS BronzeBadges,
        NULL                                      AS ReputationRank,
        NULL                                      AS GoldBadgeRank,
        MAX(ra.RecentDate)                        AS RecentDate,
        NULL                                      AS TopTags,
        'Aggregate'                               AS MemberLevel
FROM    RankedUsers    ru
JOIN    RecentActivity ra ON ra.Id = ru.Id
WHERE   ru.Reputation >= 1000
  AND   ra.RecentDate > CURRENT_DATE - INTERVAL '180 days';
