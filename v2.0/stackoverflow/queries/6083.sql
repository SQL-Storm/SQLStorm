-- {"query": "6083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 387}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
BadgesSummary AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS total_badges,
        SUM(B.Class) AS badge_points
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
VotesPerPost AS (
    SELECT
        V.PostId,
        COUNT(*) AS total_votes,
        MAX(CASE WHEN V.VoteTypeId = 2 THEN V.BountyAmount ELSE 0 END) AS max_bounty
    FROM
        Votes V
    GROUP BY
        V.PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    RP.DisplayName,
    RP.Reputation,
    B.total_badges,
    B.badge_points,
    COALESCE(VP.total_votes, 0) AS total_votes,
    COALESCE(VP.max_bounty, 0) AS max_bounty
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgesSummary B ON RP.OwnerUserId = B.UserId
LEFT JOIN 
    VotesPerPost VP ON RP.Id = VP.PostId
WHERE 
    RP.rank <= 10
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
FETCH FIRST 100 ROWS ONLY;