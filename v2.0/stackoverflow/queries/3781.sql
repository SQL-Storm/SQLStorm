-- {"query": "3781.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2456}
WITH recent_posts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Tags,
        p.PostTypeId
    FROM Posts p
    WHERE p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
),
post_tags AS (
    SELECT
        rp.OwnerUserId          AS UserId,
        TRIM(BOTH '<>' FROM UNNEST(
            string_to_array(
                REPLACE(rp.Tags, '><', ','), ','
            )
        ))                      AS TagName
    FROM recent_posts rp
    WHERE rp.Tags IS NOT NULL
),
user_tag_counts AS (
    SELECT
        ut.UserId,
        ut.TagName,
        COUNT(*)                               AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY ut.UserId ORDER BY COUNT(*) DESC) AS rn
    FROM post_tags ut
    GROUP BY ut.UserId, ut.TagName
),
top_user_tags AS (
    SELECT
        utc.UserId,
        utc.TagName,
        utc.TagCount
    FROM user_tag_counts utc
    WHERE utc.rn = 1
),
badge_agg AS (
    SELECT
        b.UserId,
        COUNT(*)                                 AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze
    FROM Badges b
    GROUP BY b.UserId
),
post_votes AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    GROUP BY v.PostId
),
user_question_score AS (
    SELECT
        u.Id                                          AS UserId,
        COALESCE(SUM(p.Score),0)                      AS TotalScore,
        COALESCE(AVG(p.Score),0)                      AS AvgScore,
        COALESCE(MIN(p.CreationDate), DATE '1900-01-01') AS FirstQuestionDate
    FROM Users u
    LEFT JOIN Posts p
        ON u.Id = p.OwnerUserId
       AND p.PostTypeId = 1
    GROUP BY u.Id
),
user_recent_activity AS (
    SELECT
        ua.Id                                        AS UserId,
        MAX(p.LastActivityDate)                      AS LastActivity,
        COUNT(DISTINCT p.Id)                         AS RecentQuestionCount,
        SUM(COALESCE(pv.UpVotes,0))                  AS RecentUpVotes,
        SUM(COALESCE(pv.DownVotes,0))                AS RecentDownVotes
    FROM Users ua
    LEFT JOIN Posts p
        ON ua.Id = p.OwnerUserId
       AND p.PostTypeId = 1
       AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '7' DAY
    LEFT JOIN post_votes pv
        ON p.Id = pv.PostId
    GROUP BY ua.Id
)
SELECT
    u.Id                                            AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COALESCE(ba.TotalBadges,0)                      AS BadgeCount,
    COALESCE(ba.Gold,0)                             AS GoldBadges,
    COALESCE(ba.Silver,0)                           AS SilverBadges,
    COALESCE(ba.Bronze,0)                           AS BronzeBadges,
    COALESCE(uqs.TotalScore,0)                      AS TotalQuestionScore,
    ROUND(COALESCE(uqs.AvgScore,0),2)               AS AvgQuestionScore,
    COALESCE(tut.TagName,'(none)')                  AS TopTag,
    COALESCE(tut.TagCount,0)                        AS TopTagPostCount,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    CASE
        WHEN u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7' DAY THEN 1
        ELSE 0
    END                                            AS ActiveLastWeek,
    COALESCE(ura.RecentQuestionCount,0)            AS QuestionsLastWeek,
    COALESCE(ura.RecentUpVotes,0)                  AS UpVotesLastWeek,
    COALESCE(ura.RecentDownVotes,0)                AS DownVotesLastWeek,
    CASE
        WHEN uqs.FirstQuestionDate > CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR THEN 'Newcomer'
        WHEN u.Reputation >= 20000 THEN 'Veteran'
        ELSE 'Established'
    END                                            AS UserTier
FROM Users u
LEFT JOIN badge_agg ba       ON u.Id = ba.UserId
LEFT JOIN user_question_score uqs ON u.Id = uqs.UserId
LEFT JOIN top_user_tags tut ON u.Id = tut.UserId
LEFT JOIN user_recent_activity ura ON u.Id = ura.UserId
WHERE u.Reputation > 1000

UNION ALL

SELECT
    -1                                            AS UserId,
    'Aggregated'                                  AS DisplayName,
    SUM(u.Reputation)                             AS Reputation,
    NULL                                          AS CreationDate,
    SUM(COALESCE(ba.TotalBadges,0))               AS BadgeCount,
    SUM(COALESCE(ba.Gold,0))                      AS GoldBadges,
    SUM(COALESCE(ba.Silver,0))                    AS SilverBadges,
    SUM(COALESCE(ba.Bronze,0))                    AS BronzeBadges,
    SUM(COALESCE(uqs.TotalScore,0))               AS TotalQuestionScore,
    ROUND(AVG(COALESCE(uqs.AvgScore,0)),2)        AS AvgQuestionScore,
    NULL                                          AS TopTag,
    NULL                                          AS TopTagPostCount,
    NULL                                          AS ReputationRank,
    NULL                                          AS ActiveLastWeek,
    SUM(COALESCE(ura.RecentQuestionCount,0))      AS QuestionsLastWeek,
    SUM(COALESCE(ura.RecentUpVotes,0))            AS UpVotesLastWeek,
    SUM(COALESCE(ura.RecentDownVotes,0))          AS DownVotesLastWeek,
    NULL                                          AS UserTier
FROM Users u
LEFT JOIN badge_agg ba       ON u.Id = ba.UserId
LEFT JOIN user_question_score uqs ON u.Id = uqs.UserId
LEFT JOIN user_recent_activity ura ON u.Id = ura.UserId
WHERE u.CreationDate < DATE '2008-01-01'

ORDER BY Reputation DESC
LIMIT 20;