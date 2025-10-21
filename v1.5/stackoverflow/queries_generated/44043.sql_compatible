WITH cte_post_history AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ph.Text,
        ph.ContentLicense,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS rn
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (2, 5, 8)
),
cte_votes AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        v.CreationDate,
        v.UserId,
        v.BountyAmount,
        ROW_NUMBER() OVER (PARTITION BY v.PostId, v.VoteTypeId ORDER BY v.CreationDate) AS rn
    FROM 
        Votes v
    WHERE 
        v.VoteTypeId IN (2, 3, 5, 7, 10)
),
cte_comments AS (
    SELECT 
        c.PostId,
        c.Score,
        c.CreationDate,
        c.UserId,
        c.ContentLicense,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate) AS rn
    FROM 
        Comments c
)
SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CreationDate AS PostCreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastEditDate,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.ContentLicense AS PostContentLicense,
    ph1.CreationDate AS InitialBodyCreationDate,
    ph1.Text AS InitialBody,
    ph1.ContentLicense AS InitialBodyContentLicense,
    ph2.CreationDate AS LastEditBodyCreationDate,
    ph2.Text AS LastEditBody,
    ph2.ContentLicense AS LastEditBodyContentLicense,
    v1.CreationDate AS FirstUpVoteDate,
    v1.UserId AS FirstUpVoterId,
    v2.CreationDate AS LastUpVoteDate,
    v2.UserId AS LastUpVoterId,
    v3.CreationDate AS FirstDownVoteDate,
    v3.UserId AS FirstDownVoterId,
    v4.CreationDate AS LastDownVoteDate,
    v4.UserId AS LastDownVoterId,
    v5.CreationDate AS FavoriteCreationDate,
    v5.UserId AS FavoriteUserId,
    c1.CreationDate AS FirstCommentCreationDate,
    c1.Score AS FirstCommentScore,
    c1.UserId AS FirstCommentUserId,
    c1.ContentLicense AS FirstCommentContentLicense,
    c2.CreationDate AS LastCommentCreationDate,
    c2.Score AS LastCommentScore,
    c2.UserId AS LastCommentUserId,
    c2.ContentLicense AS LastCommentContentLicense
FROM 
    Posts p
LEFT JOIN 
    cte_post_history ph1 ON p.Id = ph1.PostId AND ph1.rn = 1
LEFT JOIN
    cte_post_history ph2 ON p.Id = ph2.PostId AND ph2.rn = (SELECT MAX(rn) FROM cte_post_history WHERE PostId = p.Id)
LEFT JOIN
    cte_votes v1 ON p.Id = v1.PostId AND v1.VoteTypeId = 2 AND v1.rn = 1
LEFT JOIN
    cte_votes v2 ON p.Id = v2.PostId AND v2.VoteTypeId = 2 AND v2.rn = (SELECT MAX(rn) FROM cte_votes WHERE PostId = p.Id AND VoteTypeId = 2)
LEFT JOIN
    cte_votes v3 ON p.Id = v3.PostId AND v3.VoteTypeId = 3 AND v3.rn = 1
LEFT JOIN
    cte_votes v4 ON p.Id = v4.PostId AND v4.VoteTypeId = 3 AND v4.rn = (SELECT MAX(rn) FROM cte_votes WHERE PostId = p.Id AND VoteTypeId = 3)
LEFT JOIN
    cte_votes v5 ON p.Id = v5.PostId AND v5.VoteTypeId = 5 AND v5.rn = 1
LEFT JOIN
    cte_comments c1 ON p.Id = c1.PostId AND c1.rn = 1
LEFT JOIN
    cte_comments c2 ON p.Id = c2.PostId AND c2.rn = (SELECT MAX(rn) FROM cte_comments WHERE PostId = p.Id)