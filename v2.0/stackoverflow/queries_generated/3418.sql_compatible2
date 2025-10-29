WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(p.PostCount,0)                         AS PostCount,
           COALESCE(p.TotalScore,0)                        AS TotalScore,
           COALESCE(a.AnswerCount,0)                       AS AnswerCount,
           COALESCE(a.AcceptedCount,0)                     AS AcceptedCount,
           CASE 
               WHEN COALESCE(a.AnswerCount,0)=0 THEN NULL
               ELSE (COALESCE(a.AcceptedCount,0) * 1.0 / a.AnswerCount)
           END                                            AS AcceptanceRate,
           COALESCE(b.GoldBadgeCount,0)                    AS GoldBadges,
           COALESCE(b.SilverBadgeCount,0)                  AS SilverBadges,
           COALESCE(b.BronzeBadgeCount,0)                  AS BronzeBadges,
           COALESCE(v.UpVoteCount,0) - COALESCE(v.DownVoteCount,0) AS VoteScore,
           (SELECT MAX(CreationDate) FROM Posts p2 WHERE p2.OwnerUserId = u.Id) AS LastPostDate,
           (SELECT MAX(CreationDate) FROM Votes v2 WHERE v2.UserId = u.Id)     AS LastVoteDate
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId,
               COUNT(*)                AS PostCount,
               SUM(Score)              AS TotalScore
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT p.OwnerUserId,
               COUNT(*) FILTER (WHERE p.PostTypeId = 2)                                    AS AnswerCount,
               COUNT(*) FILTER (WHERE p.PostTypeId = 2 AND p.Id = q.AcceptedAnswerId)       AS AcceptedCount
        FROM Posts p
        LEFT JOIN Posts q ON q.Id = p.ParentId AND q.PostTypeId = 1
        GROUP BY p.OwnerUserId
    ) a ON a.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId,
               COUNT(*) FILTER (WHERE Class = 1) AS GoldBadgeCount,
               COUNT(*) FILTER (WHERE Class = 2) AS SilverBadgeCount,
               COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadgeCount
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT UserId,
               COUNT(*) FILTER (WHERE VoteTypeId = 2) AS UpVoteCount,
               COUNT(*) FILTER (WHERE VoteTypeId = 3) AS DownVoteCount
        FROM Votes
        GROUP BY UserId
    ) v ON v.UserId = u.Id
),

RecentActivity AS (
    SELECT us.Id,
           GREATEST(us.LastPostDate, us.LastVoteDate) AS LastActivity
    FROM UserStats us
),

TagPopularity AS (
    SELECT t.TagName,
           t.Count,
           ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE
),

TopTags AS (
    SELECT TagName, Count
    FROM TagPopularity
    WHERE TagRank <= 10
),

PostTags AS (
    -- split Tags like '<tag1><tag2>' into rows by replacing angle brackets and splitting on '><'
    SELECT p.OwnerUserId,
           NULLIF(TRIM(tag), '') AS TagName
    FROM Posts p,
    LATERAL (
        SELECT TRIM(value) AS tag
        FROM (
            SELECT regexp_replace(p.Tags, '^<|>$', '') AS tstr
        ) s,
        LATERAL (
            SELECT value
            FROM (SELECT UNNEST(string_to_array(s.tstr, '><')) AS value) u
        ) split
    ) split2
    WHERE p.PostTypeId = 1
)

SELECT us.Id,
       us.DisplayName,
       us.Reputation,
       us.PostCount,
       us.TotalScore,
       ROUND(us.AcceptanceRate * 100, 2)            AS AcceptancePct,
       us.GoldBadges,
       us.SilverBadges,
       us.BronzeBadges,
       us.VoteScore,
       ra.LastActivity,
       CASE 
           WHEN ra.LastActivity IS NULL                                                         THEN 'Never Active'
           WHEN ra.LastActivity < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year') THEN 'Stale'
           ELSE 'Active'
       END                                            AS ActivityStatus,
       STRING_AGG(DISTINCT tt.TagName, ', ') 
           FILTER (WHERE tt.TagName IS NOT NULL)       AS TopTagsUsed
FROM UserStats us
LEFT JOIN RecentActivity ra ON ra.Id = us.Id
LEFT JOIN PostTags pt ON pt.OwnerUserId = us.Id
LEFT JOIN TopTags tt ON tt.TagName = pt.TagName
GROUP BY us.Id, us.DisplayName, us.Reputation, us.PostCount, us.TotalScore,
         us.AcceptanceRate, us.GoldBadges, us.SilverBadges, us.BronzeBadges,
         us.VoteScore, ra.LastActivity
HAVING COUNT(*) FILTER (WHERE tt.TagName IS NOT NULL) > 0

UNION ALL

SELECT NULL, '---', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL

ORDER BY Reputation DESC NULLS LAST
LIMIT 100;