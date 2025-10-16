WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS AuthorDisplayName, 
        u.Reputation,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS HighestBountyAmount
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
PostTags AS (
    SELECT 
        p.Id AS PostId, 
        t.TagName
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Id = t.ExcerptPostId
    WHERE 
        p.PostTypeId = 1
),
PostHistoryCTE AS (
    SELECT 
        ph.Id,
        ph.PostId, 
        ph.PostHistoryTypeId, 
        ph.CreationDate, 
        ph.UserId, 
        ph.UserDisplayName, 
        ph.Text, 
        ph.Comment
    FROM 
        PostHistory ph
    WHERE 
        ph.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '6 months'
),
TopAuthors AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(p.Id) AS PostCount
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(p.Id) > 10
),
PostActivity AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.LastEditDate, 
        p.LastActivityDate, 
        p.Score, 
        p.ViewCount, 
        COUNT(DISTINCT ph.Id) AS EditCount
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.LastEditDate, p.LastActivityDate, p.Score, p.ViewCount
),
-- Helper to aggregate ordered distinct comments in a portable way:
RecentHistoryAgg AS (
    SELECT
        ph.PostId,
        STRING_AGG(ph.Comment, ', ' ORDER BY ph.CreationDate DESC) AS RecentHistoryAllComments,
        -- produce distinct comments by using a sub-aggregation (dialects without DISTINCT+ORDER BY support)
        (SELECT STRING_AGG(cmt, ', ')
         FROM (
            SELECT DISTINCT ph2.Comment AS cmt, MAX(ph2.CreationDate) AS max_cd
            FROM PostHistory ph2
            WHERE ph2.PostId = ph.PostId
            GROUP BY ph2.Comment
            ORDER BY max_cd DESC
         ) sub
        ) AS RecentHistoryDistinctComments
    FROM PostHistoryCTE ph
    GROUP BY ph.PostId
)
SELECT 
    rp.Id AS PostId, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.AuthorDisplayName, 
    rp.Reputation, 
    rp.VoteCount, 
    rp.UpVoteCount, 
    rp.DownVoteCount, 
    rp.HighestBountyAmount, 
    STRING_AGG(DISTINCT pt.TagName, ', ') AS Tags, 
    -- prefer distinct ordered comments; fallback to ordered all comments if distinct list is NULL
    COALESCE(rha.RecentHistoryDistinctComments, rha.RecentHistoryAllComments) AS RecentHistory,
    pa.EditCount AS ActivityCount,
    ta.DisplayName AS TopAuthorDisplayName
FROM 
    RecentPosts rp
JOIN 
    PostTags pt ON rp.Id = pt.PostId
LEFT JOIN 
    PostHistoryCTE ph ON rp.Id = ph.PostId
LEFT JOIN 
    RecentHistoryAgg rha ON rp.Id = rha.PostId
LEFT JOIN 
    PostActivity pa ON rp.Id = pa.Id
LEFT JOIN 
    TopAuthors ta ON ta.Id = rp.Id
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.AuthorDisplayName, rp.Reputation, rp.VoteCount, rp.UpVoteCount, rp.DownVoteCount, rp.HighestBountyAmount, pa.EditCount, ta.DisplayName, rha.RecentHistoryDistinctComments, rha.RecentHistoryAllComments
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.CreationDate DESC
LIMIT 100;