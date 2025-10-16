WITH RecentUsers AS (
    SELECT 
        Id AS UserId, 
        DisplayName, 
        CreationDate
    FROM 
        Users
    WHERE 
        CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
),
UserActivity AS (
    SELECT 
        u.UserId, 
        COUNT(DISTINCT p.Id) AS PostCount, 
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM 
        RecentUsers u
    LEFT JOIN Posts p ON u.UserId = p.OwnerUserId
    LEFT JOIN Comments c ON u.UserId = c.UserId
    GROUP BY u.UserId
),
UserPostScores AS (
    SELECT 
        p.OwnerUserId AS UserId, 
        SUM(p.Score) AS TotalPostScore, 
        AVG(p.Score) AS AvgPostScore
    FROM 
        Posts p
    WHERE 
        PostTypeId IN (1, 2) 
        AND p.OwnerUserId IN (SELECT UserId FROM RecentUsers)
    GROUP BY p.OwnerUserId
),
TopBadges AS (
    SELECT 
        b.UserId, 
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames
    FROM 
        Badges b
    WHERE 
        b.UserId IN (SELECT UserId FROM RecentUsers) 
        AND b.Class = 1
    GROUP BY b.UserId
),
FilteredPosts AS (
    SELECT 
        p.Id,
        p.Title, 
        p.Body,
        CASE 
            WHEN p.Score > 10 THEN 'Hot' 
            WHEN p.Score < 0 THEN 'Cold' 
            ELSE 'Neutral' 
        END AS Popularity
    FROM 
        Posts p
    WHERE 
        p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month'
        AND p.Score IS NOT NULL
),
CommentSummary AS (
    SELECT 
        c.PostId, 
        COUNT(c.Id) AS CommentCount, 
        STRING_AGG(c.Text, '; ') AS AllComments
    FROM 
        Comments c
    GROUP BY c.PostId
),
DetailedPostAnalysis AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        cs.CommentCount,
        cs.AllComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        -- include Popularity by joining to FilteredPosts to ensure column exists
        fp.Popularity
    FROM 
        Posts p
    LEFT JOIN CommentSummary cs ON cs.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN FilteredPosts fp ON fp.Id = p.Id
    WHERE 
        p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month'
    GROUP BY 
        p.Id, p.Title, p.Score, cs.CommentCount, cs.AllComments, fp.Popularity
),
CombinedResults AS (
    SELECT 
        ua.UserId, 
        ru.DisplayName,
        ua.PostCount, 
        ua.CommentCount,
        ups.TotalPostScore,
        ups.AvgPostScore,
        tb.BadgeNames
    FROM 
        UserActivity ua
    JOIN RecentUsers ru ON ua.UserId = ru.UserId
    LEFT JOIN UserPostScores ups ON ua.UserId = ups.UserId
    LEFT JOIN TopBadges tb ON ua.UserId = tb.UserId
)
SELECT 
    cr.UserId,
    cr.DisplayName,
    cr.PostCount,
    cr.CommentCount,
    cr.TotalPostScore,
    cr.AvgPostScore,
    cr.BadgeNames,
    dp.Title AS RecentPostTitle, 
    dp.Popularity AS PostPopularity,
    dp.Score AS RecentPostScore,
    dp.CommentCount AS RecentPostCommentCount,
    dp.AllComments AS RecentPostAllComments,
    dp.UpVotes,
    dp.DownVotes
FROM 
    CombinedResults cr
LEFT JOIN DetailedPostAnalysis dp ON cr.UserId = dp.Id
ORDER BY 
    cr.TotalPostScore DESC NULLS LAST, dp.UpVotes DESC NULLS LAST, dp.DownVotes ASC NULLS LAST;