WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
PostRanks AS (
    SELECT 
        Id, 
        Title, 
        CreationDate, 
        Score, 
        ViewCount, 
        OwnerDisplayName, 
        Reputation, 
        VoteCount, 
        UpVoteCount, 
        DownVoteCount,
        ROW_NUMBER() OVER (ORDER BY Score DESC, ViewCount DESC, Reputation DESC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY ViewCount DESC) AS ViewRank,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS RepRank
    FROM 
        RecentPosts
),
RankedPosts AS (
    SELECT 
        Id,
        Title,
        CreationDate,
        Score,
        ViewCount,
        OwnerDisplayName,
        Reputation,
        VoteCount,
        UpVoteCount,
        DownVoteCount,
        ScoreRank,
        ViewRank,
        RepRank,
        (ScoreRank + ViewRank + RepRank) AS TotalRank
    FROM 
        PostRanks
),
TopContributors AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(p.Id) AS PostCount, 
        SUM(p.Score) AS TotalScore, 
        SUM(p.ViewCount) AS TotalViewCount, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount, 
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY 
        u.Id, u.DisplayName
),
TopContributorRanks AS (
    SELECT 
        Id, 
        DisplayName, 
        PostCount, 
        TotalScore, 
        TotalViewCount, 
        UpVoteCount, 
        DownVoteCount, 
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, TotalViewCount DESC, PostCount DESC) AS Rank
    FROM 
        TopContributors
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.Reputation, 
    rp.VoteCount, 
    rp.UpVoteCount, 
    rp.DownVoteCount, 
    rp.TotalRank, 
    tc.DisplayName AS TopContributorDisplayName, 
    tc.Rank AS TopContributorRank
FROM 
    RankedPosts rp
LEFT JOIN 
    TopContributorRanks tc ON rp.OwnerDisplayName = tc.DisplayName
WHERE 
    rp.TotalRank <= 10
ORDER BY 
    rp.TotalRank, 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.Reputation DESC;