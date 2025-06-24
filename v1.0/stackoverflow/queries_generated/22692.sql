WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        RANK() OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) AS ScoreRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON v.PostId = p.Id
    GROUP BY 
        u.Id
),
PostHistoryStats AS (
    SELECT 
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS ReopenedDate,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors
    FROM 
        PostHistory ph
    GROUP BY 
        ph.PostId
),
TopPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.ViewCount,
        p.CreationDate,
        phs.ClosedDate,
        phs.ReopenedDate,
        COALESCE(phs.UniqueEditors, 0) AS UniqueEditors,
        RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank
    FROM 
        Posts p
    LEFT JOIN 
        PostHistoryStats phs ON p.Id = phs.PostId
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.TotalQuestions,
    us.TotalScore,
    us.TotalUpVotes,
    us.TotalDownVotes,
    th.Title AS TopPostTitle,
    th.ViewCount AS TopPostViewCount,
    th.ClosedDate,
    th.ReopenedDate,
    th.UniqueEditors,
    CASE 
        WHEN th.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN th.ReopenedDate IS NOT NULL THEN 'Reopened'
        ELSE 'Active'
    END AS PostStatus
FROM 
    UserStats us
LEFT JOIN 
    TopPosts th ON th.ViewRank = 1
WHERE 
    us.ScoreRank <= 10
ORDER BY 
    us.Reputation DESC, 
    th.ViewCount DESC;

-- Additional processing to filter users who have either:
-- - More than 10 total posts
-- - Greater than or equal to 100 reputation
-- - Have at least one closed post or have not edited any posts in over a week.
SELECT 
    *
FROM (
    SELECT 
        *,
        DENSE_RANK() OVER (PARTITION BY PostStatus ORDER BY Reputation DESC) AS StatusRank
    FROM (
        SELECT 
            UserId,
            DisplayName,
            Reputation,
            TotalPosts,
            TotalQuestions,
            TotalScore,
            TotalUpVotes,
            TotalDownVotes,
            TopPostTitle,
            TopPostViewCount,
            ClosedDate,
            ReopenedDate,
            UniqueEditors,
            PostStatus
        FROM (
            SELECT 
                us.UserId,
                us.DisplayName,
                us.Reputation,
                us.TotalPosts,
                us.TotalQuestions,
                us.TotalScore,
                us.TotalUpVotes,
                us.TotalDownVotes,
                th.Title AS TopPostTitle,
                th.ViewCount AS TopPostViewCount,
                th.ClosedDate,
                th.ReopenedDate,
                th.UniqueEditors,
                CASE 
                    WHEN th.ClosedDate IS NOT NULL THEN 'Closed'
                    WHEN th.ReopenedDate IS NOT NULL THEN 'Reopened'
                    ELSE 'Active'
                END AS PostStatus
            FROM 
                UserStats us
            LEFT JOIN 
                TopPosts th ON th.ViewRank = 1
            WHERE 
                us.TotalPosts > 10 OR us.Reputation >= 100
        ) AS FilteredUsers
    ) AS FinalUsers
) AS RankedUsers
WHERE 
    StatusRank <= 5
ORDER BY 
    PostStatus, 
    Reputation DESC;
