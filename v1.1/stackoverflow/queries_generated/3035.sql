-- {"query": "3035.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1043} 
WITH TagUsageCTE AS (
    SELECT 
        T.TagName,
        COUNT(*) AS TagUsageCount
    FROM 
        Tags T
    LEFT JOIN 
        Posts P ON T.ExcerptPostId = P.Id OR T.WikiPostId = P.Id
    WHERE 
        P.PostTypeId = 1
        AND T.IsModeratorOnly = FALSE
    GROUP BY 
        T.TagName
),
PostsWithTimestamp AS (
    SELECT
        P.Id,
        P.Title,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.Tags,
        P.PostTypeId,
        CASE 
            WHEN P.PostTypeId = 1 THEN 'Question'
            WHEN P.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeLabel,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate ASC) AS PostRank
    FROM
        Posts P
    WHERE
        P.CreationDate BETWEEN '2020-01-01' AND '2020-12-31'
),
TopQuestions AS (
    SELECT
        WP.Id AS QuestionId,
        WP.Title,
        WP.CreationDate,
        WP.Score,
        WP.ViewCount,
        WP.Tags,
        WP.PostTypeLabel,
        ROW_NUMBER() OVER (PARTITION BY WP.PostTypeId ORDER BY WP.Score DESC, WP.CreationDate ASC) AS Rank
    FROM
        PostsWithTimestamp WP
    WHERE
        WP.PostTypeId = 1
        AND WP.Rank <= 10
),
AnswerCounts AS (
    SELECT
        P.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount
    FROM
        Posts P
    WHERE
        P.PostTypeId = 2
        AND P.ParentId IS NOT NULL
    GROUP BY
        P.ParentId
),
RecentEdits AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS EditDate,
        U.DisplayName AS EditorName,
        PH.UserId AS EditorUserId,
        PH.Comment
    FROM
        PostHistory PH
    LEFT JOIN
        Users U ON PH.UserId = U.Id
    WHERE
        PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
),
PostStats AS (
    SELECT
        P.Id,
        P.Title,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.Tags,
        PC.AnswerCount,
        RE.EditDate,
        RE.EditorName,
        RE.Comment AS LastEditComment,
        DATEDIFF(day, P.CreationDate, MAX(RE.EditDate)) AS DaysToLastEdit
    FROM
        Posts P
    LEFT JOIN
        AnswerCounts PC ON P.Id = PC.QuestionId
    LEFT JOIN
        RecentEdits RE ON P.Id = RE.PostId
    GROUP BY
        P.Id,
        P.Title,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.Tags,
        PC.AnswerCount,
        RE.EditDate,
        RE.EditorName,
        RE.Comment
),
MainQuery AS (
    SELECT
        TS.*,
        TU.TagUsageCount,
        EXISTS (
            SELECT 1 FROM Votes V WHERE V.PostId = TS.Id AND V.VoteTypeId = 2
        ) AS IsUpvoted,
        EXISTS (
            SELECT 1 FROM Votes V WHERE V.PostId = TS.Id AND V.VoteTypeId = 3
        ) AS IsDownvoted,
        (
            SELECT COUNT(*) FROM Comments C WHERE C.PostId = TS.Id
        ) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY TS.PostTypeId ORDER BY TS.Score DESC) AS OverallRank
    FROM
        PostStats TS
    LEFT JOIN
        TagUsageCTE TU ON TU.TagName = ANY(string_to_array(substring(TS.Tags, 2, length(TS.Tags)-2), '><'))
)
SELECT
    MQ.Id,
    MQ.Title,
    MQ.CreationDate,
    MQ.Score,
    MQ.ViewCount,
    MQ.AnswerCount,
    MQ.LastEditDate,
    MQ.EditorName,
    MQ.LastEditComment,
    MQ.DaysToLastEdit,
    MQ.TagUsageCount,
    MQ.IsUpvoted,
    MQ.IsDownvoted,
    MQ.CommentCount,
    MQ.OverallRank,
    (MQ.OverallRank <= 15) AS TopOverall,
    CASE WHEN MQ.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END AS PostTypeLabel
FROM
    MainQuery MQ
WHERE
    MQ.DaysToLastEdit IS NOT NULL
    AND MQ.DaysToLastEdit <= 365
ORDER BY
    MQ.OverallRank
LIMIT 100;