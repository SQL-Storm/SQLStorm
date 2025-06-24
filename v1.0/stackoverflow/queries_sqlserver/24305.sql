
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        SUM(ISNULL(p.ViewCount, 0)) AS TotalViews,
        SUM(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS TotalScore
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
), 
PostHistoryDetails AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        COUNT(*) AS ChangeCount
    FROM 
        PostHistory ph
    WHERE 
        ph.CreationDate >= CAST('2024-10-01 12:34:56' AS DATETIME) - INTERVAL '1 year'
    GROUP BY 
        ph.PostId, ph.PostHistoryTypeId
), 
RecentVotes AS (
    SELECT 
        v.PostId,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Votes v
    JOIN 
        VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE 
        v.CreationDate >= CAST('2024-10-01 12:34:56' AS DATETIME) - INTERVAL '6 months'
    GROUP BY 
        v.PostId
),
MergedDetails AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        ISNULL(up.PostCount, 0) AS UserPosts,
        ISNULL(up.TotalViews, 0) AS UserViews,
        ISNULL(up.TotalScore, 0) AS UserScore,
        ISNULL(phd.ChangeCount, 0) AS HistoryCount,
        ISNULL(rv.VoteCount, 0) AS RecentVoteCount,
        rv.UpVotes,
        rv.DownVotes
    FROM 
        Posts p
    LEFT JOIN 
        UserPostStats up ON p.OwnerUserId = up.UserId
    LEFT JOIN 
        PostHistoryDetails phd ON p.Id = phd.PostId
    LEFT JOIN 
        RecentVotes rv ON p.Id = rv.PostId
    WHERE 
        p.CreationDate >= '2023-01-01'
)
SELECT 
    md.PostId,
    md.Title,
    md.CreationDate,
    md.UserPosts,
    md.UserViews,
    md.UserScore,
    md.HistoryCount,
    md.RecentVoteCount,
    md.UpVotes,
    md.DownVotes,
    CASE 
        WHEN md.RecentVoteCount > 50 THEN 'Very Active'
        WHEN md.RecentVoteCount > 20 THEN 'Active'
        ELSE 'Inactive' 
    END AS ActivityLevel
FROM 
    MergedDetails md
ORDER BY 
    md.UserScore DESC, 
    md.RecentVoteCount DESC 
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
