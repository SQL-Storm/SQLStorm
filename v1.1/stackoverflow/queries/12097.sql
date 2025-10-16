WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY P.Id) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY P.Id) AS DownVotes,
        COUNT(C.Id) OVER (PARTITION BY P.Id) AS CommentCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (2, 5, 24) THEN 1 ELSE 0 END) OVER (PARTITION BY P.Id) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) OVER (PARTITION BY P.Id) AS ClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) OVER (PARTITION BY P.Id) AS ReopenedDate
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
), 
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
), 
PostTagCounts AS (
    SELECT 
        P.Id,
        COUNT(T.Id) AS TagCount
    FROM 
        Posts P
    CROSS JOIN LATERAL (
        SELECT part_trimmed
        FROM (
            SELECT TRIM('>' FROM part) AS part_trimmed
            FROM UNNEST(string_to_array(COALESCE(P.Tags, ''), '>')) AS part
        ) sub
        WHERE part_trimmed <> ''
    ) tagparts
    LEFT JOIN Tags T ON T.TagName = tagparts.part_trimmed
    GROUP BY 
        P.Id
)
SELECT 
    RP.Id AS PostId,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.PostRank,
    RP.UpVotes,
    RP.DownVotes,
    RP.CommentCount,
    RP.EditCount,
    RP.ClosedDate,
    RP.ReopenedDate,
    TU.Id AS TopUserId,
    TU.DisplayName AS TopUserDisplayName,
    TU.Reputation,
    TU.GoldBadges,
    TU.SilverBadges,
    TU.BronzeBadges,
    TU.UserRank,
    COALESCE(PTC.TagCount, 0) AS TagCount
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id
LEFT JOIN 
    PostTagCounts PTC ON RP.Id = PTC.Id
WHERE 
    RP.PostRank <= 10
    AND TU.UserRank <= 10
ORDER BY 
    RP.PostRank, 
    TU.UserRank;