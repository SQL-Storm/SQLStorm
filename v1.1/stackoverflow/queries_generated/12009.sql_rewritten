-- {"query": "12009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 869} 
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Title,
        P.Tags,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS Rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopPosts AS (
    SELECT 
        Id, 
        PostTypeId, 
        Title, 
        Tags, 
        Score, 
        ViewCount, 
        CreationDate, 
        OwnerDisplayName
    FROM 
        RankedPosts
    WHERE 
        Rank <= 10
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostsCount,
        COUNT(DISTINCT C.Id) AS CommentsCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
PostTags AS (
    SELECT 
        P.Id,
        UNNEST(string_to_array(P.Tags, '<')) AS Tag
    FROM 
        Posts P
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        AVG(P.Score) AS AvgScore
    FROM 
        Tags T
    JOIN 
        PostTags PT ON T.TagName = PT.Tag
    JOIN 
        Posts P ON PT.Id = P.Id
    GROUP BY 
        T.TagName
),
PostHistoryStats AS (
    SELECT 
        P.Id,
        COUNT(PH.Id) AS HistoryCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate
    FROM 
        Posts P
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
    GROUP BY 
        P.Id
),
ComplexPredicates AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Title,
        P.Tags,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName AS OwnerDisplayName,
        COALESCE(PHS.HistoryCount, 0) AS HistoryCount,
        COALESCE(PHS.LastEditDate, P.CreationDate) AS LastEditDate
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        PostHistoryStats PHS ON P.Id = PHS.Id
    WHERE 
        P.Score > 10 AND 
        P.CreationDate > cast('2024-10-01' as date) - INTERVAL '1 year' AND 
        (P.Tags LIKE '%sql%' OR P.Tags LIKE '%database%')
)
SELECT 
    CPS.PostTypeId,
    CPS.Title,
    CPS.Tags,
    CPS.Score,
    CPS.ViewCount,
    CPS.CreationDate,
    CPS.OwnerDisplayName,
    CPS.HistoryCount,
    CPS.LastEditDate,
    TS.PostCount,
    TS.AvgScore
FROM 
    ComplexPredicates CPS
JOIN 
    PostTags PT ON CPS.Id = PT.Id
JOIN 
    TagStats TS ON PT.Tag = TS.TagName
ORDER BY 
    CPS.Score DESC, 
    CPS.CreationDate;