WITH q AS (
    SELECT
        p.Id                                     AS PostId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Tags,
        p.Title,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '90 days'
),
tagged AS (
    SELECT
        q.PostId,
        q.OwnerUserId,
        q.Score,
        q.CreationDate,
        q.Title,
        q.ViewCount,
        q.CommentCount,
        q.FavoriteCount,
        q.AcceptedAnswerId,
        t.TagName
    FROM q
    CROSS JOIN LATERAL (SELECT unnest(string_to_array(q.Tags, ',')) AS TagName) AS t
),
vote_stats AS (
    SELECT
        pv.PostId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')                       AS UpVotes,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod')                     AS DownVotes,
        SUM(vb.BountyAmount)                                           AS TotalBounty
    FROM Votes pv
    JOIN VoteTypes vt ON vt.Id = pv.VoteTypeId
    LEFT JOIN LATERAL (
        SELECT vb.BountyAmount
        FROM Votes vb
        WHERE vb.VoteTypeId IN (8, 9) AND vb.PostId = pv.PostId
    ) vb ON TRUE
    GROUP BY pv.PostId
)
SELECT
    t.TagName,
    COUNT(DISTINCT t.PostId)                                   AS QuestionCount,
    AVG(t.Score)                                               AS AvgScore,
    MAX(t.ViewCount)                                           AS MaxViews,
    SUM(t.CommentCount)                                        AS TotalComments,
    SUM(t.FavoriteCount)                                       AS TotalFavorites,
    SUM(v.UpVotes)                                             AS TotalUpVotes,
    SUM(v.DownVotes)                                           AS TotalDownVotes,
    SUM(v.TotalBounty)                                         AS TotalBounty
FROM tagged t
LEFT JOIN vote_stats v ON v.PostId = t.PostId
GROUP BY t.TagName
ORDER BY QuestionCount DESC, TotalUpVotes DESC
LIMIT 20;