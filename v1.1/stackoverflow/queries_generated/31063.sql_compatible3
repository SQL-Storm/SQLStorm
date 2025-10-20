WITH RecentQuestions AS (
    SELECT P.Id AS QuestionId, P.Title, P.CreationDate, P.ViewCount, U.DisplayName AS OwnerName
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId = 1
      AND P.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
),
TopTags AS (
    SELECT T.TagName, COUNT(P.Id) AS QuestionCount
    FROM Posts P
    JOIN LATERAL (
      SELECT CAST(s AS INTEGER) AS tag_id
      FROM unnest(string_to_array(P.Tags, ',')) AS s
    ) tag_ids ON TRUE
    JOIN Tags T ON T.Id = tag_ids.tag_id
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
    SELECT RQ.QuestionId, RQ.Title, RQ.CreationDate, RQ.ViewCount, RQ.OwnerName, COALESCE(TT.TagName, NULL) AS TagName, COALESCE(QV.UpVotes, 0) AS UpVotes, COALESCE(QV.DownVotes, 0) AS DownVotes
    FROM RecentQuestions RQ
    LEFT JOIN QuestionVotes QV ON RQ.QuestionId = QV.PostId
    LEFT JOIN (
      SELECT P.Id AS PostId, T.TagName
      FROM Posts P
      JOIN LATERAL (
        SELECT CAST(s AS INTEGER) AS tag_id
        FROM unnest(string_to_array(P.Tags, ',')) AS s
      ) tag_ids ON TRUE
      JOIN Tags T ON T.Id = tag_ids.tag_id
      WHERE P.PostTypeId = 1
        AND T.TagName IN (SELECT TagName FROM TopTags)
    ) TT ON RQ.QuestionId = TT.PostId
)
SELECT QS.QuestionId, QS.Title, QS.CreationDate, QS.ViewCount, QS.OwnerName,
       COALESCE(QS.UpVotes, 0) AS UpVotes, COALESCE(QS.DownVotes, 0) AS DownVotes,
       STRING_AGG(QS.TagName, ', ') AS Tags
FROM QuestionStatistics QS
GROUP BY QS.QuestionId, QS.Title, QS.CreationDate, QS.ViewCount, QS.OwnerName, QS.UpVotes, QS.DownVotes
ORDER BY QS.ViewCount DESC, QS.UpVotes DESC
LIMIT 10;