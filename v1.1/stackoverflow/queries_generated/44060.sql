-- {"query": "44060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 583}

WITH cte AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(u.Reputation, 0) AS UserReputation,
        COALESCE(u.UpVotes, 0) AS UserUpvotes,
        COALESCE(u.DownVotes, 0) AS UserDownvotes,
        COALESCE(u.Views, 0) AS UserViews,
        COALESCE(b.Id, 0) AS BadgeCount,
        CASE
            WHEN p.PostTypeId = 1 THEN 1
            WHEN p.PostTypeId = 2 THEN 2
            ELSE 0
        END AS PostTypeRank,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsClosed,
        COALESCE(pl.LinkTypeId, 0) AS LinkTypeId,
        COALESCE(pt.Name, '') AS PostTypeName,
        COALESCE(vt.Name, '') AS VoteTypeName,
        COALESCE(cr.Name, '') AS CloseReasonName
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN VoteTypes vt ON pl.LinkTypeId = vt.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes cr ON CAST(ph.Comment AS INT) = cr.Id
)
SELECT
    *
FROM cte
WHERE
    PostTypeRank IN (1, 2)
    AND IsClosed = 0
    AND LinkTypeId <> 3
ORDER BY
    UserReputation DESC,
    Score DESC,
    ViewCount DESC,
    AnswerCount DESC,
    CommentCount DESC,
    FavoriteCount DESC,
    BadgeCount DESC;
