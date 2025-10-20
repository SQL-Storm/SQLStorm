-- {"query": "12073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 753} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(B.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
PostCommentCounts AS (
    SELECT 
        PostId,
        COUNT(*) AS CommentCount
    FROM 
        Comments
    GROUP BY 
        PostId
),
PostHistorySummary AS (
    SELECT 
        PostId,
        COUNT(CASE WHEN PostHistoryTypeId IN (1, 2, 3) THEN 1 END) AS InitialRevisions,
        COUNT(CASE WHEN PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS Edits,
        COUNT(CASE WHEN PostHistoryTypeId IN (7, 8, 9) THEN 1 END) AS Rollbacks,
        COUNT(CASE WHEN PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN 1 END) AS ModerationActions
    FROM 
        PostHistory
    GROUP BY 
        PostId
),
PostTags AS (
    SELECT 
        P.Id,
        STRING_AGG(T.TagName, ', ') AS Tags
    FROM 
        Posts P
    JOIN 
        lateral unnest(string_to_array(P.Tags, '<')) WITH ORDINALITY AS Tags(TagName, ordinality)
    JOIN 
        Tags T ON Tags.TagName = T.TagName
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        P.Id
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.PostRank,
    COALESCE(PCC.CommentCount, 0) AS CommentCount,
    PHS.InitialRevisions,
    PHS.Edits,
    PHS.Rollbacks,
    PHS.ModerationActions,
    PT.Tags,
    TU.DisplayName AS TopUser,
    TU.Reputation,
    TU.BadgeCount
FROM 
    RankedPosts RP
LEFT JOIN 
    PostCommentCounts PCC ON RP.Id = PCC.PostId
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN 
    PostTags PT ON RP.Id = PT.Id
LEFT JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id
WHERE 
    RP.PostRank <= 10
ORDER BY 
    RP.PostRank, 
    TU.UserRank;
