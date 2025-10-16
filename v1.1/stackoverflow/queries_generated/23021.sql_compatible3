WITH ActiveUsers AS (
    SELECT u.Id AS UserId,
           u.Reputation,
           u.DisplayName,
           COUNT(p.Id) AS PostCount,
           SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
           SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore,
           ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankInLocation,
           u.Location
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000 AND (u.Location IS NOT NULL OR u.WebsiteUrl LIKE '%stackoverflow%')
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location
    HAVING COUNT(p.Id) > 10
),
TaggedPosts AS (
    SELECT p.Id AS PostId,
           p.Tags,
           p.Score,
           (
             SELECT COUNT(*)
             FROM (
               SELECT trim(tag_val) AS tag_val
               FROM (
                 SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><') AS tag_val
               ) AS inner_split
             ) AS tag_array
             WHERE lower(tag_val) LIKE '%sql%'
           ) AS SqlTagCount
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.CreationDate > DATE '2020-01-01'
),
UserBadges AS (
    SELECT b.UserId,
           COUNT(b.Id) AS GoldBadges,
           MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    WHERE b.Class = 1 AND b.TagBased = TRUE
    GROUP BY b.UserId
),
CorrelatedVotes AS (
    SELECT v.PostId,
           SUM(v.BountyAmount) AS TotalBounty,
           (
             SELECT AVG(c.Score)
             FROM Comments c
             WHERE c.PostId = v.PostId AND c.Score > 0
           ) AS AvgCommentScore
    FROM Votes v
    WHERE v.VoteTypeId IN (8, 9)
    GROUP BY v.PostId
)
SELECT au.UserId,
       au.DisplayName,
       au.Reputation,
       au.PostCount,
       au.QuestionScore + au.AnswerScore AS TotalScore,
       COALESCE(ub.GoldBadges, 0) AS GoldBadges,
       tp.Tags,
       cv.TotalBounty,
       CASE WHEN au.RankInLocation = 1 THEN 'Top in Location' ELSE 'Other' END AS LocationStatus,
       RANK() OVER (ORDER BY au.Reputation DESC) AS OverallRank
FROM ActiveUsers au
LEFT JOIN UserBadges ub ON au.UserId = ub.UserId
INNER JOIN Posts p ON au.UserId = p.OwnerUserId
LEFT JOIN TaggedPosts tp ON p.Id = tp.PostId
LEFT JOIN CorrelatedVotes cv ON p.Id = cv.PostId
WHERE (tp.SqlTagCount > 0) OR (cv.AvgCommentScore IS NULL)
UNION ALL
SELECT u.Id,
       u.DisplayName,
       u.Reputation,
       0 AS PostCount,
       0 AS TotalScore,
       0 AS GoldBadges,
       CAST(NULL AS VARCHAR) AS Tags,
       CAST(NULL AS NUMERIC) AS TotalBounty,
       'Inactive' AS LocationStatus,
       CAST(NULL AS INTEGER) AS OverallRank
FROM Users u
WHERE u.Id NOT IN (SELECT UserId FROM ActiveUsers) AND u.Reputation BETWEEN 1 AND 100
ORDER BY TotalScore DESC NULLS LAST;