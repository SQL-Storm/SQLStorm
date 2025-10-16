WITH ActiveUsers AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.UpVotes - U.DownVotes AS NetVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        U.CreationDate > DATE '2020-01-01'
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes
    HAVING 
        COUNT(DISTINCT P.Id) > 5
), 

TopPosters AS (
    SELECT 
        P.Id AS PostId,
        P.OwnerUserId,
        P.Score,
        P.ViewCount,
        array_length(string_to_array(P.Tags, '><'), 1) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS ScoreRank,
        P.CreationDate
    FROM 
        Posts P
    WHERE 
        P.PostTypeId = 1
        AND P.CreationDate > DATE '2020-01-01'
),

HighScorePosts AS (
    SELECT 
        PostId,
        OwnerUserId,
        Score,
        ViewCount,
        TagCount
    FROM 
        TopPosters
    WHERE 
        ScoreRank <= 3
        AND TagCount > 3
),

MergedData AS (
    SELECT 
        A.UserId,
        A.DisplayName,
        A.NetVotes,
        A.TotalPosts,
        COALESCE(SUM(CAST(H.Score AS BIGINT) * CAST(H.ViewCount AS BIGINT)), 0) AS WeightedViewScore
    FROM 
        ActiveUsers A
    LEFT JOIN 
        HighScorePosts H ON A.UserId = H.OwnerUserId
    GROUP BY 
        A.UserId, A.DisplayName, A.NetVotes, A.TotalPosts
)

SELECT 
    M.UserId,
    M.DisplayName,
    M.NetVotes,
    M.TotalPosts,
    M.WeightedViewScore,
    B.Name AS BadgeName,
    COUNT(B.Id) AS BadgeCount
FROM 
    MergedData M
LEFT JOIN 
    Badges B ON M.UserId = B.UserId AND B.Class = 1
GROUP BY 
    M.UserId, M.DisplayName, M.NetVotes, M.TotalPosts, M.WeightedViewScore, B.Name
ORDER BY 
    M.WeightedViewScore DESC, M.NetVotes DESC;