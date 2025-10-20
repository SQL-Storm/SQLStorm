WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 END) OVER (PARTITION BY P.Id) AS UpVotes,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 END) OVER (PARTITION BY P.Id) AS DownVotes,
        COUNT(C.Id) OVER (PARTITION BY P.Id) AS CommentCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (2, 5, 24) THEN 1 ELSE 0 END) OVER (PARTITION BY P.Id) AS EditCount,
        -- normalize tags into a delimited string without surrounding angle brackets; use '|' as delimiter
        CASE
          WHEN P.Tags IS NULL OR P.Tags = '' THEN NULL
          ELSE REPLACE(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM P.Tags)), '><', '|')
        END AS TagsDelimited
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
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        AVG(P.Score) AS AvgScore
    FROM 
        Tags T
    LEFT JOIN 
        Posts P ON (
            P.Tags IS NOT NULL
            AND ('|' || REPLACE(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM P.Tags)), '><', '|') || '|') LIKE '%|' || T.TagName || '|%'
        )
    GROUP BY 
        T.TagName
),
PostWithTags AS (
    SELECT 
        P.Id,
        P.Title,
        CASE
          WHEN P.Tags IS NULL OR P.Tags = '' THEN NULL
          ELSE REPLACE(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM P.Tags)), '><', '|')
        END AS TagsDelimited
    FROM 
        Posts P
),
TagCombinations AS (
    SELECT 
        PT.Id,
        -- reconstruct ordered tag list by splitting on '|' is not standard; approximate by returning distinct tags concatenated
        -- use LISTAGG/STRING_AGG where available; standard SQL uses LISTAGG in some dialects; use COALESCE to handle NULL
        COALESCE(STRING_AGG(T.TagName, '|' ORDER BY T.TagName), NULL) AS TagCombination
    FROM 
        PostWithTags PT
    JOIN 
        Tags T ON ('|' || PT.TagsDelimited || '|') LIKE '%|' || T.TagName || '|%'
    GROUP BY 
        PT.Id
),
PostTagRanks AS (
    SELECT 
        TC.Id,
        TC.TagCombination,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT P.Id) DESC) AS TagCombinationRank
    FROM 
        TagCombinations TC
    JOIN 
        Posts P ON TC.Id = P.Id
    GROUP BY 
        TC.Id, TC.TagCombination
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.PostRank,
    RP.UpVotes,
    RP.DownVotes,
    RP.CommentCount,
    RP.EditCount,
    TU.DisplayName AS TopUser,
    TU.Reputation AS TopUserReputation,
    TU.QuestionCount,
    TU.AnswerCount,
    TU.UserRank,
    TS.TagName,
    TS.PostCount,
    TS.TotalScore,
    TS.AvgScore,
    PTR.TagCombination,
    PTR.TagCombinationRank
FROM 
    RankedPosts RP
LEFT JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id
LEFT JOIN 
    TagStats TS ON TS.TagName IS NOT NULL AND RP.TagsDelimited IS NOT NULL AND ('|' || RP.TagsDelimited || '|') LIKE '%|' || TS.TagName || '|%'
LEFT JOIN 
    PostTagRanks PTR ON RP.Id = PTR.Id
WHERE 
    RP.PostRank <= 10
    AND (TU.UserRank IS NULL OR TU.UserRank <= 10)
ORDER BY 
    RP.Score DESC, RP.CreationDate;