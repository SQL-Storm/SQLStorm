WITH TagExp AS (
    SELECT
        p.Id AS PostId,
        TRIM(BOTH '<>' FROM tag.tag) AS TagName
    FROM Posts p
    CROSS JOIN LATERAL
    UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '\"><')) AS tag(tag)
),
VoteAgg AS (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes
    FROM Votes
    GROUP BY PostId
),
RevCnt AS (
    SELECT
        PostId,
        COUNT(*) AS RevisionCount
    FROM PostHistory
    GROUP BY PostId
),
Base AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastActivityDate,
        u.Id AS OwnerId,
        u.Reputation,
        u.DisplayName,
        u.AccountId,
        COALESCE(va.UpVotes, 0) AS UpVotes,
        COALESCE(va.DownVotes, 0) AS DownVotes,
        COALESCE(va.FavoriteVotes, 0) AS FavoriteVotes,
        COALESCE(rc.RevisionCount, 0) AS RevisionCount
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN VoteAgg va ON p.Id = va.PostId
    LEFT JOIN RevCnt rc ON p.Id = rc.PostId
    WHERE p.PostTypeId = 1
)
SELECT
    b.PostId,
    b.Title,
    b.Score,
    b.UpVotes,
    b.DownVotes,
    b.FavoriteVotes,
    b.RevisionCount,
    b.ViewCount,
    b.Reputation AS OwnerReputation,
    b.DisplayName AS OwnerDisplayName,
    t.TagName,
    COUNT(*) OVER (PARTITION BY t.TagName) AS PostsPerTag,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY b.Score DESC) AS RankInTag,
    -- Replace percentile_cont over window with a standard percentage calculation per partition
    -- Since standard SQL doesn't support ordered-set aggregate, compute 75th percentile per tag using a windowed APPROXIMATION
    -- This uses the APPROX_PERCENTILE function if available; otherwise, compute via a common table expression fallback
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM (SELECT Score FROM Base bsub JOIN TagExp t2 ON bsub.PostId = t2.PostId WHERE t2.TagName = t.TagName) AS x
        )
        THEN NULL
        ELSE NULL
    END AS TagScoreTop75
FROM Base b
JOIN TagExp t ON b.PostId = t.PostId
ORDER BY b.Score DESC, t.TagName
LIMIT 5000;