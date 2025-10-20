-- {"query": "12066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 739} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        P.LastActivityDate,
        P.Tags,
        COUNT(C.Id) OVER (PARTITION BY P.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopPosts AS (
    SELECT 
        Id,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount,
        OwnerUserId,
        OwnerDisplayName,
        LastActivityDate,
        Tags,
        CommentCount
    FROM 
        RankedPosts
    WHERE 
        PostRank <= 10
),
UserBadges AS (
    SELECT 
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (2, 5, 6) THEN 1 ELSE NULL END) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS ClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS ReopenedDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
),
PostVotes AS (
    SELECT 
        V.PostId,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpVotes,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownVotes
    FROM 
        Votes V
    GROUP BY 
        V.PostId
)
SELECT 
    TP.Id,
    TP.PostTypeId,
    TP.CreationDate,
    TP.Score,
    TP.ViewCount,
    TP.OwnerUserId,
    TP.OwnerDisplayName,
    TP.LastActivityDate,
    TP.Tags,
    TP.CommentCount,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.BronzeBadges,
    PHS.EditCount,
    PHS.ClosedDate,
    PHS.ReopenedDate,
    PV.UpVotes,
    PV.DownVotes
FROM 
    TopPosts TP
LEFT JOIN 
    UserBadges UBS ON TP.OwnerUserId = UBS.UserId
LEFT JOIN 
    PostHistorySummary PHS ON TP.Id = PHS.PostId
LEFT JOIN 
    PostVotes PV ON TP.Id = PV.PostId
ORDER BY 
    TP.Score DESC, 
    TP.CreationDate;
