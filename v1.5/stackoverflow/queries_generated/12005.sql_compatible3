WITH PostStats AS (
    SELECT 
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 2) AS UpVotes,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 3) AS DownVotes,
        COUNT(DISTINCT C.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC) AS RankByScore,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.ViewCount DESC) AS RankByViewCount
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    GROUP BY 
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, U.DisplayName
),
TopPosts AS (
    SELECT 
        PostId,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount,
        OwnerUserId,
        OwnerDisplayName,
        UpVotes,
        DownVotes,
        CommentCount,
        RankByScore,
        RankByViewCount
    FROM 
        PostStats
    WHERE 
        RankByScore <= 10 OR RankByViewCount <= 10
),
UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2) AS AnswersGiven,
        COUNT(DISTINCT C.Id) AS CommentsMade,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
BadgeSummary AS (
    SELECT 
        B.UserId,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadges
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS TotalEdits,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
),
PostTagSummary AS (
    SELECT 
        P.Id AS PostId,
        STRING_AGG(T.TagName, ', ') AS Tags
    FROM 
        Posts P
    JOIN LATERAL (
        SELECT TagName
        FROM unnest(string_to_array(substr(P.Tags, 2, length(P.Tags) - 2), '><')) AS TagName
    ) AS TagName ON true
    JOIN 
        Tags T ON TagName.TagName = T.TagName
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        P.Id
)
SELECT 
    TOP.PostId,
    TOP.PostTypeId,
    TOP.CreationDate,
    TOP.Score,
    TOP.ViewCount,
    TOP.OwnerUserId,
    TOP.OwnerDisplayName,
    TOP.UpVotes,
    TOP.DownVotes,
    TOP.CommentCount,
    TOP.RankByScore,
    TOP.RankByViewCount,
    UA.Reputation,
    UA.QuestionsAsked,
    UA.AnswersGiven,
    UA.CommentsMade,
    UA.UpVotesGiven,
    UA.DownVotesGiven,
    BS.GoldBadges,
    BS.SilverBadges,
    BS.BronzeBadges,
    PHS.TotalEdits,
    PHS.LastEditDate,
    PTS.Tags
FROM 
    TopPosts TOP
JOIN 
    UserActivity UA ON TOP.OwnerUserId = UA.UserId
LEFT JOIN 
    BadgeSummary BS ON TOP.OwnerUserId = BS.UserId
LEFT JOIN 
    PostHistorySummary PHS ON TOP.PostId = PHS.PostId
LEFT JOIN 
    PostTagSummary PTS ON TOP.PostId = PTS.PostId
ORDER BY 
    TOP.Score DESC, TOP.ViewCount DESC;