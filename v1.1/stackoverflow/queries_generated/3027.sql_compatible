WITH UserAnswerStats AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(A.Id) FILTER (WHERE A.PostTypeId = 2) AS AnswerCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        AVG(A.Score) AS AverageAnswerScore,
        MAX(A.LastActivityDate) AS LastActive
    FROM 
        Users U
        LEFT JOIN Posts A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2
        LEFT JOIN Votes V ON A.Id = V.PostId
    GROUP BY 
        U.Id, U.DisplayName
),
AnswerTags AS (
    SELECT 
        A.Id AS AnswerId,
        ARRAY_AGG(T.TagName) AS Tags
    FROM 
        Posts A
        LEFT JOIN LATERAL (
            SELECT 
                unnest(string_to_array(substring(A.Tags, 2, length(A.Tags)-2), '><')) AS TagName
        ) T ON TRUE
        LEFT JOIN Tags GT ON T.TagName = GT.TagName
    WHERE 
        A.PostTypeId = 2
    GROUP BY 
        A.Id
),
RecentEdits AS (
    SELECT 
        PH.PostId,
        COUNT(*) AS EditCount,
        MAX(PH.CreationDate) AS LastEdit
    FROM 
        PostHistory PH
        JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE 
        PHT.Name ILIKE '%Edit%'
    GROUP BY 
        PH.PostId
),
AnswerLinkCount AS (
    SELECT 
        PL.PostId,
        COUNT(*) AS LinkCount
    FROM 
        PostLinks PL
        JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
    WHERE 
        LT.Name ILIKE '%duplicate%'
    GROUP BY 
        PL.PostId
)
SELECT 
    U.UserId,
    U.DisplayName,
    U.AnswerCount,
    U.UpVotesReceived,
    U.DownVotesReceived,
    U.AverageAnswerScore,
    U.LastActive,
    at.Tags,
    re.EditCount,
    re.LastEdit,
    COALESCE(alc.LinkCount, 0) AS DuplicateLinks
FROM 
    UserAnswerStats U
    LEFT JOIN AnswerTags at ON U.UserId = at.AnswerId
    LEFT JOIN RecentEdits re ON U.UserId = re.PostId
    LEFT JOIN AnswerLinkCount alc ON U.UserId = alc.PostId
WHERE 
    U.AnswerCount > 10 AND 
    U.LastActive > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
ORDER BY 
    U.AnswerCount DESC, U.UpVotesReceived DESC
LIMIT 100;