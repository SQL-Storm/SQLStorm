WITH FavoriteVotes AS (
    SELECT
        p.Id AS post_id,
        p.Title,
        u.DisplayName,
        COUNT(v.Id) AS FavoriteCount,
        COALESCE(
            STRING_AGG(DISTINCT CASE WHEN vt.Name LIKE 'Actual Delivered Link %' THEN vt.Name ELSE NULL END, ','),
            ''
        ) AS DeliveredLinks
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY p.Id, p.Title, u.DisplayName
)
SELECT
    fv.post_id,
    fv.Title,
    fv.DisplayName,
    fv.FavoriteCount,
    fv.DeliveredLinks
FROM FavoriteVotes fv
ORDER BY fv.FavoriteCount DESC;