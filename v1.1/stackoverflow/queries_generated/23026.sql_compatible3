WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        EXTRACT(YEAR FROM u.CreationDate) AS JoinYear
    FROM Users u
    WHERE u.Reputation > 1000
      AND u.LastAccessDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
),
PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        -- convert tags like '<sql><other>' into JSON array string '["sql","other"]' in a dialect-neutral way
        ('["' || REPLACE(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><', '","') || '"]') AS TagArray,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        AVG(NULLIF(p.CommentCount, 0)) AS AvgCommentsPerPost,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        p.CreationDate
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.CreationDate > DATE '2010-01-01'
      AND (p.Title LIKE '%SQL%' OR p.Tags LIKE '%<sql>%')
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.ViewCount, p.Title, p.Tags, p.CommentCount, p.CreationDate
    HAVING COUNT(v.Id) > 5
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        MAX(b.Date) AS LatestBadgeDate,
        STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS BadgeNames
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
),
CombinedData AS (
    SELECT 
        au.UserId,
        au.DisplayName,
        au.Reputation,
        au.ReputationRank,
        au.UserLocation,
        au.JoinYear,
        ps.PostId,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.Title,
        ps.TagArray,
        ps.VoteCount,
        ps.UpVotes,
        ps.AvgCommentsPerPost,
        ps.PreviousScore,
        bs.BadgeCount,
        bs.LatestBadgeDate,
        bs.BadgeNames,
        CASE 
            WHEN ps.Score > ps.PreviousScore THEN 'Improved'
            WHEN ps.Score < ps.PreviousScore THEN 'Declined'
            ELSE 'Stable'
        END AS ScoreTrend,
        COALESCE((SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = ps.PostId AND c.Score > 0), 0) AS PositiveComments
    FROM ActiveUsers au
    INNER JOIN PostStats ps ON au.UserId = ps.OwnerUserId
    LEFT JOIN BadgeSummary bs ON au.UserId = bs.UserId
    WHERE au.ReputationRank <= 100
      AND (
            (
                POSITION('"sql"' IN ps.TagArray) > 0
            )
            OR lower(ps.Title) LIKE '%database%'
          )
      AND ps.PreviousScore IS NOT NULL
    UNION
    SELECT 
        au.UserId,
        au.DisplayName,
        au.Reputation,
        au.ReputationRank,
        au.UserLocation,
        au.JoinYear,
        NULL AS PostId,
        NULL AS PostTypeId,
        NULL AS Score,
        NULL AS ViewCount,
        NULL AS Title,
        NULL AS TagArray,
        0 AS VoteCount,
        0 AS UpVotes,
        NULL AS AvgCommentsPerPost,
        NULL AS PreviousScore,
        bs.BadgeCount,
        bs.LatestBadgeDate,
        bs.BadgeNames,
        'No Posts' AS ScoreTrend,
        0 AS PositiveComments
    FROM ActiveUsers au
    LEFT JOIN BadgeSummary bs ON au.UserId = bs.UserId
    WHERE au.ReputationRank <= 100
      AND NOT EXISTS (SELECT 1 FROM PostStats ps WHERE ps.OwnerUserId = au.UserId)
)
SELECT 
    cd.*,
    DENSE_RANK() OVER (PARTITION BY cd.JoinYear ORDER BY cd.Reputation DESC) AS YearlyRank,
    (cd.DisplayName || ' (' || cd.UserLocation || ')') AS UserInfo,
    CASE 
        WHEN COALESCE(cd.BadgeCount, 0) > 10 THEN 'Veteran'
        WHEN COALESCE(cd.BadgeCount, 0) BETWEEN 5 AND 10 THEN 'Experienced'
        ELSE 'Novice'
    END AS BadgeLevel,
    (cd.UpVotes * 1.0 / NULLIF(cd.VoteCount, 0)) AS UpVoteRatio
FROM CombinedData cd
WHERE cd.PositiveComments > 0 OR cd.ScoreTrend = 'Improved'
ORDER BY cd.Reputation DESC, cd.Score DESC;