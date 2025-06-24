WITH RankedPosts AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.Tags,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS Rank,
        COALESCE((SELECT COUNT(*) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2), 0) AS UpVotes,
        COALESCE((SELECT COUNT(*) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3), 0) AS DownVotes
    FROM 
        Posts P
    WHERE 
        P.PostTypeId = 1 AND 
        P.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '30 days')
),
TopPosts AS (
    SELECT 
        RP.PostId,
        RP.Title,
        RP.CreationDate,
        RP.Score,
        RP.ViewCount,
        RP.Tags,
        RP.Rank,
        RP.UpVotes,
        RP.DownVotes,
        CASE 
            WHEN RP.Rank = 1 THEN 'Top Question'
            ELSE 'Other Question'
        END AS PostRankCategory
    FROM 
        RankedPosts RP
    WHERE 
        RP.Rank <= 5
),
PostStatistics AS (
    SELECT 
        TP.PostId,
        TP.Title,
        TP.CreationDate,
        TP.Score,
        TP.ViewCount,
        TP.Tags,
        CASE 
            WHEN TP.UpVotes > TP.DownVotes THEN 'Positive'
            WHEN TP.UpVotes < TP.DownVotes THEN 'Negative'
            ELSE 'Neutral'
        END AS VoteSentiment,
        DATE_PART('year', CURRENT_TIMESTAMP - TP.CreationDate) AS AgeInYears,
        (
            SELECT COUNT(*) 
            FROM Comments C 
            WHERE C.PostId = TP.PostId
        ) AS CommentCount,
        COALESCE(MAX(B.Class) FILTER (WHERE B.UserId = P.OwnerUserId), 0) AS TopBadgeClass
    FROM 
        TopPosts TP
    LEFT JOIN 
        Badges B ON B.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = TP.PostId)
    GROUP BY 
        TP.PostId, TP.Title, TP.CreationDate, TP.Score, TP.ViewCount, TP.Tags, TP.UpVotes, TP.DownVotes
)
SELECT 
    PS.PostId,
    PS.Title,
    PS.CreationDate,
    PS.Score,
    PS.ViewCount,
    PS.Tags,
    PS.VoteSentiment,
    PS.AgeInYears,
    PS.CommentCount,
    CASE 
        WHEN PS.TopBadgeClass = 1 THEN 'Gold'
        WHEN PS.TopBadgeClass = 2 THEN 'Silver'
        WHEN PS.TopBadgeClass = 3 THEN 'Bronze'
        ELSE 'No Badge'
    END AS TopBadge
FROM 
    PostStatistics PS
WHERE 
    PS.AgeInYears BETWEEN 0 AND 1
ORDER BY 
    PS.Score DESC 
LIMIT 10;

WITH RECURSIVE RelatedPosts AS (
    SELECT 
        PL.RelatedPostId,
        1 AS Level
    FROM 
        PostLinks PL
    WHERE 
        PL.PostId IN (SELECT PostId FROM TopPosts)

    UNION ALL

    SELECT 
        PL.RelatedPostId,
        RP.Level + 1
    FROM 
        PostLinks PL
    JOIN 
        RelatedPosts RP ON PL.PostId = RP.RelatedPostId
)
SELECT 
    RP.RelatedPostId,
    COUNT(*) AS ConnectionDepth
FROM 
    RelatedPosts RP
GROUP BY 
    RP.RelatedPostId
HAVING 
    COUNT(*) > 1 
ORDER BY 
    ConnectionDepth DESC;
