-- {"query": "1093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 419} 

WITH UserVoteStats AS (
    SELECT 
        U.Id AS UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionPosts
    FROM Users U
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Posts P ON V.PostId = P.Id
    WHERE U.Reputation > 1000
    GROUP BY U.Id
),
PostHistoryData AS (
    SELECT 
        PH.PostId,
        P.Title,
        COUNT(PH.Id) AS EditCount,
        MAX(PH.CreationDate) AS LastEditDate
    FROM PostHistory PH
    JOIN Posts P ON PH.PostId = P.Id
    WHERE PH.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY PH.PostId, P.Title
),
PopularTags AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount
    FROM Tags T
    JOIN Posts P ON T.Id = P.Id
    WHERE P.PostTypeId = 1
    GROUP BY T.TagName
    ORDER BY PostCount DESC
    LIMIT 10
)
SELECT 
    U.DisplayName,
    US.UpVotes,
    US.DownVotes,
    US.TotalPosts,
    US.QuestionPosts,
    PHD.Title,
    PHD.EditCount,
    PHD.LastEditDate,
    PT.TagName
FROM UserVoteStats US
LEFT JOIN PostHistoryData PHD ON US.TotalPosts > 0
LEFT JOIN PopularTags PT ON PT.PostCount > 5 AND PHD.EditCount > 3
ORDER BY US.UpVotes DESC, US.QuestionPosts DESC
OFFSET 10
LIMIT 5;
