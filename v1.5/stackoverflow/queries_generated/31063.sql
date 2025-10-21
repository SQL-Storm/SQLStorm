-- {"query": "31063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 425} 

WITH RecentQuestions AS (
    SELECT P.Id AS QuestionId, P.Title, P.CreationDate, P.ViewCount, U.DisplayName AS OwnerName
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId = 1 AND P.CreationDate >= NOW() - INTERVAL '30 days'
),
TopTags AS (
    SELECT T.TagName, COUNT(P.Id) AS QuestionCount
    FROM Posts P
    JOIN Tags T ON T.Id = ANY(STRING_TO_ARRAY(P.Tags, ',')::int[])
    WHERE P.PostTypeId = 1
    GROUP BY T.TagName
    ORDER BY QuestionCount DESC
    LIMIT 5
),
QuestionVotes AS (
    SELECT V.PostId, SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes V
    GROUP BY V.PostId
),
QuestionStatistics AS (
    SELECT RQ.QuestionId, RQ.Title, RQ.CreationDate, RQ.ViewCount, RQ.OwnerName, TV.UpVotes, TV.DownVotes, T.TagName
    FROM RecentQuestions RQ
    LEFT JOIN QuestionVotes TV ON RQ.QuestionId = TV.PostId
    LEFT JOIN TopTags T ON T.QuestionCount > 0
)
SELECT QS.QuestionId, QS.Title, QS.CreationDate, QS.ViewCount, QS.OwnerName, COALESCE(QS.UpVotes, 0) AS UpVotes, COALESCE(QS.DownVotes, 0) AS DownVotes, STRING_AGG(QS.TagName, ', ') AS Tags
FROM QuestionStatistics QS
GROUP BY QS.QuestionId, QS.Title, QS.CreationDate, QS.ViewCount, QS.OwnerName, QS.UpVotes, QS.DownVotes
ORDER BY QS.ViewCount DESC, QS.UpVotes DESC
LIMIT 10;
