WITH RECURSIVE RecursiveVotesCTE AS (
    SELECT 
        v.Id AS VoteId,
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        COALESCE(v.BountyAmount, 0) AS BountyAmount,
        1 AS Level,
        v.CreationDate
    FROM Votes v
    WHERE v.VoteTypeId IN (8, 9)  -- BountyStart and BountyClose

    UNION ALL

    SELECT
        v2.Id AS VoteId,
        v2.PostId,
        v2.VoteTypeId,
        v2.UserId,
        COALESCE(v2.BountyAmount, 0) AS BountyAmount,
        r.Level + 1 AS Level,
        v2.CreationDate
    FROM Votes v2
    JOIN RecursiveVotesCTE r
      ON v2.PostId = r.PostId
     AND v2.CreationDate > r.CreationDate
    WHERE v2.VoteTypeId IN (8, 9)
)
SELECT
    r.VoteId,
    r.PostId,
    r.VoteTypeId,
    r.UserId,
    r.BountyAmount,
    r.Level,
    r.CreationDate
FROM RecursiveVotesCTE r
ORDER BY r.PostId, r.CreationDate;