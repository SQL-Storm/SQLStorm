WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate) AS UserPostRank,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) OVER (PARTITION BY p.Id) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) OVER (PARTITION BY p.Id) AS DownVotes,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (24, 31) THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS EditCount,
        p.Tags
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
),
TopPosts AS (
    SELECT 
        Id, 
        PostTypeId, 
        CreationDate, 
        Score, 
        ViewCount, 
        OwnerUserId, 
        OwnerDisplayName, 
        UserPostRank, 
        UpVotes, 
        DownVotes, 
        CommentCount, 
        EditCount,
        Tags
    FROM 
        RankedPosts
    WHERE 
        UserPostRank <= 3
),
TagStats AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') AS TopContributors
    FROM 
        Tags t
    JOIN 
        Posts p ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    GROUP BY 
        t.TagName
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.LastActivityDate) AS LastActivityDate
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        u.DisplayName AS UserDisplayName,
        COUNT(*) OVER (PARTITION BY ph.PostId) AS TotalEdits,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS EditRank
    FROM 
        PostHistory ph
    JOIN 
        Users u ON ph.UserId = u.Id
)
SELECT 
    tp.Id,
    tp.PostTypeId,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    tp.OwnerUserId,
    tp.OwnerDisplayName,
    tp.UserPostRank,
    tp.UpVotes,
    tp.DownVotes,
    tp.CommentCount,
    tp.EditCount,
    ts.TagName,
    ts.PostCount AS TagPostCount,
    ts.TotalScore AS TagTotalScore,
    ts.AvgScore AS TagAvgScore,
    ts.TopContributors,
    ua.PostCount AS UserPostCount,
    ua.TotalScore AS UserTotalScore,
    ua.BadgeCount,
    ua.LastActivityDate,
    phs.PostHistoryTypeId,
    phs.CreationDate AS EditCreationDate,
    phs.UserDisplayName,
    phs.TotalEdits,
    phs.EditRank
FROM 
    TopPosts tp
JOIN 
    TagStats ts ON tp.Tags LIKE '%' || ts.TagName || '%'
JOIN 
    UserActivity ua ON tp.OwnerUserId = ua.UserId
LEFT JOIN 
    PostHistorySummary phs ON tp.Id = phs.PostId AND phs.EditRank = 1
ORDER BY 
    tp.Score DESC, 
    tp.CreationDate;