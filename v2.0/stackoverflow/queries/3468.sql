-- {"query": "3468.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1482}
WITH 
UserAgg AS (
    SELECT 
        u.Id                                   AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)                            AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score)                           AS AvgPostScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(p.CreationDate)                   AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v   ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentActivity AS (
    SELECT 
        ua.UserId,
        MAX(ua.ActivityDate)                AS LastActivityDate,
        COUNT(*) OVER (PARTITION BY ua.UserId) AS RecentActivityCount
    FROM (
        SELECT OwnerUserId AS UserId, CreationDate AS ActivityDate FROM Posts WHERE CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
        UNION ALL
        SELECT UserId, CreationDate FROM Comments WHERE CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
        UNION ALL
        SELECT UserId, CreationDate FROM Votes WHERE CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
    ) ua
    WHERE ua.UserId IS NOT NULL
    GROUP BY ua.UserId
),
BadgeAgg AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN COALESCE(b.TagBased, FALSE) = TRUE THEN 1 ELSE 0 END) AS TagBadgeCount,
        SUM(CASE WHEN COALESCE(b.TagBased, FALSE) = FALSE THEN 1 ELSE 0 END) AS NamedBadgeCount,
        MAX(b.Class)                                    AS HighestBadgeClass
    FROM Badges b
    GROUP BY b.UserId
),
TagUsage AS (
    SELECT 
        p.OwnerUserId                     AS UserId,
        LOWER(TRIM(BOTH '>' FROM UNNEST(string_to_array(TRIM(BOTH '<' FROM p.Tags), '><')))) AS Tag,
        COUNT(*)                          AS TagAppearances
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),
TopTagsPerUser AS (
    SELECT 
        tu.UserId,
        tu.Tag,
        tu.TagAppearances,
        ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY tu.TagAppearances DESC) AS rn
    FROM TagUsage tu
)

SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.QuestionCount,
    ua.AnswerCount,
    ROUND(ua.AvgPostScore::numeric,2)                     AS AvgScore,
    ua.UpVoteCount,
    ua.DownVoteCount,
    COALESCE(ra.LastActivityDate, ua.LastPostDate)    AS LastActivity,
    COALESCE(ra.RecentActivityCount,0)                AS RecentActions30d,
    COALESCE(ba.TagBadgeCount,0)                      AS TagBadges,
    COALESCE(ba.NamedBadgeCount,0)                    AS NamedBadges,
    COALESCE(ba.HighestBadgeClass,3)                  AS TopBadgeClass,
    STRING_AGG(CONCAT(tt.Tag, ':', CAST(tt.TagAppearances AS varchar)), ', ') 
        FILTER (WHERE tt.rn <= 5)                     AS Top5Tags,
    (SELECT MAX(LENGTH(p.Body))
     FROM Posts p
     WHERE p.OwnerUserId = ua.UserId
       AND p.PostTypeId = 2)                         AS MaxAnswerLength,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM PostLinks pl
            WHERE pl.PostId = (
                SELECT Id FROM Posts 
                WHERE OwnerUserId = ua.UserId 
                  AND PostTypeId = 1 
                ORDER BY CreationDate DESC LIMIT 1
            )
            AND pl.LinkTypeId = 3
        ) THEN 'HasDuplicateLink'
        ELSE 'NoDuplicateLink'
    END                                              AS DuplicateLinkFlag,
    CONCAT(
        LEFT(COALESCE(u.AboutMe, ''), 100),
        CASE WHEN LENGTH(COALESCE(u.AboutMe, '')) > 100 THEN '...' ELSE '' END
    )                                                AS ProfileSnippet
FROM UserAgg ua
LEFT JOIN RecentActivity ra   ON ra.UserId = ua.UserId
LEFT JOIN BadgeAgg ba         ON ba.UserId = ua.UserId
LEFT JOIN TopTagsPerUser tt   ON tt.UserId = ua.UserId
LEFT JOIN Users u             ON u.Id = ua.UserId
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.AvgPostScore,
    ua.UpVoteCount,
    ua.DownVoteCount,
    ra.LastActivityDate,
    ua.LastPostDate,
    ra.RecentActivityCount,
    ba.TagBadgeCount,
    ba.NamedBadgeCount,
    ba.HighestBadgeClass,
    tt.Tag,
    tt.TagAppearances,
    tt.rn,
    u.AboutMe
ORDER BY ua.Reputation DESC
LIMIT 100;