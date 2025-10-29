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
BadgeCounts AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(B.Id) AS badge_count
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
VoteSummary AS (
    SELECT 
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
        COUNT(V.Id) AS total_votes
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
    RP.rank,
    RP.DisplayName,
    RP.Reputation,
    BC.badge_count,
    VS.upvotes,
    VS.downvotes,
    VS.total_votes,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score > 0 THEN 'Medium'
        ELSE 'Low'
    END AS score_category,
    SUBSTRING(RP.Title FROM 1 FOR 50) AS short_title,
    CASE
        WHEN POSITION(' ' IN RP.Title) > 0 THEN SUBSTRING(RP.Title FROM 1 FOR POSITION(' ' IN RP.Title) - 1)
        ELSE RP.Title
    END AS first_word,
    CASE 
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Not Popular'
    END AS view_category
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.Id
LEFT JOIN 
    VoteSummary VS ON RP.Id = VS.PostId
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.rank,
    RP.DisplayName,
    RP.Reputation,
    RP.OwnerUserId,
    BC.badge_count,
    VS.upvotes,
    VS.downvotes,
    VS.total_votes
ORDER BY 
    RP.rank, RP.Score DESC;