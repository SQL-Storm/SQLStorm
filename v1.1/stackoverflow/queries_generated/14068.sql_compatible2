WITH cte AS (
    SELECT 
        p.Id AS PostId,
        p.CreationDate AS PostCreationDate,
        p.OwnerUserId,
        p.AnswerCount,
        p.FavoriteCount,
        p.CommentCount,
        p.Score,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        ARRAY_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags)-2))) AS Tags,
        (
            SELECT COUNT(*)
            FROM PostHistory ph
            WHERE ph.PostId = p.Id
              AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
        ) AS PostHistoryModActions,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = p.Id
        ) AS CommentCountFromComments,
        (
            SELECT COUNT(*)
            FROM Votes v
            WHERE v.PostId = p.Id
              AND v.VoteTypeId IN (2, 3)
        ) AS VoteCount,
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = p.OwnerUserId
        ) AS OwnerBadgeCount,
        (
            SELECT COUNT(*)
            FROM Posts p2
            WHERE p2.OwnerUserId = p.OwnerUserId
        ) AS OwnerPostCount,
        (
            SELECT COUNT(*)
            FROM Votes v
            WHERE v.UserId = p.OwnerUserId
        ) AS OwnerVoteCount
    FROM Posts p
    GROUP BY p.Id, p.CreationDate, p.OwnerUserId, p.AnswerCount, p.FavoriteCount, p.CommentCount, p.Score, p.AcceptedAnswerId, p.ClosedDate, p.CommunityOwnedDate, p.Tags
)
SELECT
    PostId,
    PostCreationDate,
    OwnerUserId,
    AnswerCount,
    FavoriteCount,
    -- prefer the Comments table count as authoritative
    CommentCountFromComments AS CommentCount,
    Score,
    AcceptedAnswerId,
    IsClosed,
    IsCommunityOwned,
    Tags,
    PostHistoryModActions,
    CommentCountFromComments,
    VoteCount,
    OwnerBadgeCount,
    OwnerPostCount,
    OwnerVoteCount,
    CASE 
        WHEN IsClosed = 1 THEN (
            SELECT crt.Name
            FROM PostHistory ph
            JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
            WHERE ph.PostId = cte.PostId AND ph.PostHistoryTypeId = 10
            ORDER BY ph.CreationDate DESC
            LIMIT 1
        )
        ELSE NULL
    END AS CloseReason,
    CASE
        WHEN IsCommunityOwned = 1 THEN (
            SELECT ph2.CreationDate
            FROM PostHistory ph2
            WHERE ph2.PostId = cte.PostId AND ph2.PostHistoryTypeId = 16
            ORDER BY ph2.CreationDate DESC
            LIMIT 1
        )
        ELSE NULL
    END AS CommunityOwnedDate,
    COALESCE((
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = cte.PostId AND v.VoteTypeId = 5
    ), 0) AS FavoriteVoteCount,
    COALESCE((
        SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE -1 END)
        FROM Votes v
        WHERE v.PostId = cte.PostId AND v.VoteTypeId IN (2, 3)
    ), 0) AS NetVoteCount
FROM cte;