-- {"query": "6204.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 569}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
        ROW_NUMBER() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
),
PostVotes AS (
    SELECT
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM Votes V
    GROUP BY V.PostId
),
TagCounts AS (
    SELECT
        T.ExcerptPostId AS PostId,
        T.TagName,
        COUNT(*) AS Count
    FROM Tags T
    GROUP BY T.ExcerptPostId, T.TagName
),
TopTagsAgg AS (
    SELECT
        TC.PostId,
        STRING_AGG(TC.TagName, ', ' ORDER BY TC.Count DESC) AS TopTags
    FROM TagCounts TC
    GROUP BY TC.PostId
)
SELECT 
    RP.Id, 
    RP.Title, 
    RP.Score, 
    RP.ViewCount,
    RP.CreationDate AS PostDate,
    RP.LastActivityDate,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    COALESCE(PV.UpvoteCount, 0) AS UpvoteCount,
    COALESCE(PV.DownvoteCount, 0) AS DownvoteCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High Scoring'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium Scoring'
        ELSE 'Low Scoring'
    END AS ScoreTier,
    COALESCE(TA.TopTags, '') AS TopTags,
    RP.Rank
FROM 
    RankedPosts RP
LEFT JOIN 
    PostVotes PV ON RP.Id = PV.PostId
LEFT JOIN 
    TopTagsAgg TA ON RP.Id = TA.PostId
LEFT JOIN 
    BadgeCounts BC ON RP.DisplayName = CAST(BC.UserId AS VARCHAR)
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.DisplayName, RP.Reputation, RP.LastAccessDate, BC.BadgeCount, PV.UpvoteCount, PV.DownvoteCount, TA.TopTags, RP.Rank
HAVING 
    COALESCE(PV.UpvoteCount, 0) > 5
ORDER BY 
    RP.Rank;