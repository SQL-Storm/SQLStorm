-- {"query": "54062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1504} 

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
      AND p.CreationDate >= current_date - interval '90 days'
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
    CROSS JOIN LATERAL string_to_array(q.Tags, ',') AS tarray
    JOIN LATERAL unnest(tarray) AS t(TagName) ON TRUE
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
