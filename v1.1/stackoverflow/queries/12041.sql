WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS RankByScore,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetVotes,
        COUNT(C.Id) AS CommentCount,
        STRING_AGG(T.TagName, ', ' ORDER BY T.Count DESC) AS TagList
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        LATERAL unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS Tag(TagName) ON TRUE
    LEFT JOIN 
        Tags T ON Tag.TagName = T.TagName
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.Id, P.PostTypeId, P.Score, P.ViewCount, P.CreationDate, P.OwnerUserId, U.DisplayName
), 
UserReputation AS (
    SELECT 
        U.Id,
        U.Reputation,
        U.CreationDate,
        U.DisplayName,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.Reputation, U.CreationDate, U.DisplayName
), 
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        MAX(PH.CreationDate) AS LastEditDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.RankByScore,
    RP.NetVotes,
    RP.CommentCount,
    RP.TagList,
    COALESCE(UR.Reputation, 0) AS OwnerReputation,
    COALESCE(UR.GoldBadges, 0) AS OwnerGoldBadges,
    COALESCE(UR.SilverBadges, 0) AS OwnerSilverBadges,
    COALESCE(UR.BronzeBadges, 0) AS OwnerBronzeBadges,
    COALESCE(PHS.EditCount, 0) AS EditCount,
    COALESCE(PHS.LastEditDate, RP.CreationDate) AS LastEditDate
FROM 
    RankedPosts RP
LEFT JOIN 
    UserReputation UR ON RP.OwnerUserId = UR.Id
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
WHERE 
    RP.RankByScore <= 10
ORDER BY 
    RP.PostTypeId, RP.Score DESC, RP.CreationDate;