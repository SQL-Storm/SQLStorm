WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        AVG(v.VoteCount) OVER (PARTITION BY p.PostTypeId) AS AvgScoreByPostType,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankInPostType,
        COALESCE(p.Tags, '-') AS Tags,
        p.AcceptedAnswerId,
        hp.CloseCount,
        combined.CommentCount,
        contributorTagCounts.TopContribTag
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS VoteCount
        FROM Votes
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN (
        -- Count number of times post has been closed (PostHistoryTypeId=10)
        SELECT PostId, COUNT(*) AS CloseCount
        FROM PostHistory
        WHERE PostHistoryTypeId = 10
        GROUP BY PostId
    ) hp ON hp.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) combined ON combined.PostId = p.Id
    LEFT JOIN (
        /* Build contributor top tags: first count occurrences per user+tag, then aggregate per user ordered by count.
           Some dialects (and PostgreSQL with DISTINCT+ORDER BY) require ordering by expressions present in the aggregate argument.
           We therefore first compute counts per user+tag, then aggregate tags ordered by that count.
        */
        SELECT
            tcounts.UserId,
            STRING_AGG(tcounts.TagName, ',') AS TopContribTag
        FROM (
            SELECT ph.UserId,
                   TRIM(t.TagName) AS TagName,
                   COUNT(*) AS TagCount,
                   RANK() OVER (PARTITION BY ph.UserId ORDER BY COUNT(*) DESC) AS TopRank
            FROM PostHistory ph
            JOIN Posts ps ON ph.PostId = ps.Id
            JOIN LATERAL (
                SELECT unnest(string_to_array(coalesce(ps.Tags, ''), '><')) AS TagName
            ) t ON t.TagName <> ''
            WHERE ph.UserId IS NOT NULL
            GROUP BY ph.UserId, TRIM(t.TagName)
        ) tcounts
        /* aggregate tags per user ordered by TagCount desc, then tag name asc for deterministic order */
        GROUP BY tcounts.UserId
    ) contributorTagCounts ON contributorTagCounts.UserId = p.OwnerUserId
),
LatestComments AS (
    SELECT
        c.PostId,
        c.Id AS CommentId,
        c.Text AS Text,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC, c.Id DESC) AS CommentRank
    FROM Comments c
)
SELECT
    rp.Id,
    rp.PostTypeId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.FavoriteCount,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.OwnerName,
    rp.AvgScoreByPostType,
    rp.RankInPostType,
    rp.Tags,
    rp.AcceptedAnswerId,
    rp.CloseCount,
    rp.CommentCount,
    rp.TopContribTag,
    lc.CommentId,
    lc.Text,
    lc.CommentRank
FROM RankedPosts rp
LEFT JOIN LatestComments lc ON lc.PostId = rp.Id
WHERE rp.RankInPostType = 1
GROUP BY
    rp.Id,
    rp.PostTypeId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.FavoriteCount,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.OwnerName,
    rp.AvgScoreByPostType,
    rp.RankInPostType,
    rp.Tags,
    rp.AcceptedAnswerId,
    rp.CloseCount,
    rp.CommentCount,
    rp.TopContribTag,
    lc.CommentId,
    lc.Text,
    lc.CommentRank;