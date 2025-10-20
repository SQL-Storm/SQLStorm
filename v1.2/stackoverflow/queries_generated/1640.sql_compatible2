WITH RecursiveVotesSummary AS (
    SELECT
        p.Id AS PostId,
        COALESCE(p.OwnerUserId, -1) AS OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        uv.TotalUpVotes,
        dv.TotalDownVotes,
        claim_badge.HasGold
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes
        FROM Votes
        GROUP BY PostId
    ) uv ON uv.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
        FROM Votes
        GROUP BY PostId
    ) dv ON dv.PostId = p.Id
    LEFT JOIN (
        SELECT UserId, MAX(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS HasGold
        FROM Badges
        GROUP BY UserId
    ) claim_badge ON claim_badge.UserId = p.OwnerUserId
)
SELECT
    rvs.PostId,
    rvs.OwnerUserId,
    rvs.PostTypeId,
    rvs.CreationDate,
    rvs.Score,
    rvs.ViewCount,
    rvs.AnswerCount,
    COALESCE(rvs.TotalUpVotes, 0) AS TotalUpVotes,
    COALESCE(rvs.TotalDownVotes, 0) AS TotalDownVotes,
    COALESCE(rvs.HasGold, 0) AS HasGold
FROM RecursiveVotesSummary rvs;