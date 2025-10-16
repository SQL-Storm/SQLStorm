WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Votes v 
             WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
            ), 0
        ) AS TotalVotes,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 1 
            ELSE 0 
        END AS IsClosed
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 
      AND u.Reputation > 1000
), TopUserPosts AS (
    SELECT 
        UserId,
        DisplayName,
        SUM(Score) AS TotalPostScore,
        AVG(TotalVotes) AS AvgVotesPerPost,
        COUNT(DISTINCT PostId) AS UniquePostCount,
        SUM(IsClosed) AS ClosedPostCount
    FROM RankedUserPosts
    WHERE PostRank <= 5
    GROUP BY UserId, DisplayName
), UserTags AS (
    SELECT
        p.OwnerUserId AS UserId,
        TRIM(tag) AS TagName
    FROM Posts p,
    LATERAL (
        SELECT UNNEST(
            regexp_split_to_array(
                CASE 
                    WHEN p.Tags LIKE '<%>' THEN substr(p.Tags, 2, length(p.Tags) - 2)
                    ELSE p.Tags
                END
            , '><')
        ) AS tag
    ) split
), BadgeCounts AS (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
), DistinctTags AS (
    SELECT DISTINCT UserId, TagName
    FROM UserTags
)
SELECT 
    tup.UserId,
    tup.DisplayName,
    tup.TotalPostScore,
    tup.AvgVotesPerPost,
    tup.UniquePostCount,
    tup.ClosedPostCount,
    COALESCE(b.BadgeCount, 0) AS BadgeCount,
    DENSE_RANK() OVER (ORDER BY tup.TotalPostScore DESC) AS ScoreRank,
    REPLACE(REPLACE(t.TagName, '<', ''), '>', '') AS TagName
FROM TopUserPosts tup
LEFT JOIN BadgeCounts b ON b.UserId = tup.UserId
LEFT JOIN DistinctTags t ON t.UserId = tup.UserId
WHERE tup.UniquePostCount > 1
  AND (tup.AvgVotesPerPost > 5 OR tup.TotalPostScore > 100)
ORDER BY ScoreRank, tup.TotalPostScore DESC
LIMIT 50;