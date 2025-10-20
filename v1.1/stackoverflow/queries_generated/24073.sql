-- {"query": "24073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 6023} 

WITH
    QuestionPosts AS (
        SELECT p.Id                      AS PostId,
               p.OwnerUserId,
               p.CreationDate,
               p.Score,
               p.AcceptedAnswerId,
               p.Tags
        FROM Posts p
        WHERE p.PostTypeId = 1                       -- only questions
    ),
    TagRows AS (
        SELECT qp.PostId,
               qp.OwnerUserId,
               qp.CreationDate,
               qp.Score,
               qp.AcceptedAnswerId,
               t.TagName
        FROM QuestionPosts qp
        CROSS APPLY (
            SELECT REPLACE(REPLACE(value,'<',''),'>','') AS TagName
            FROM STRING_SPLIT(qp.Tags,'><')
        ) t
    ),
    VoteSums AS (
        SELECT v.PostId,
               SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END)     AS UpVotes,
               SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END)   AS DownVotes,
               SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END)  AS Favorites
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ),
    CommentStats AS (
        SELECT c.PostId,
               COUNT(*) AS CommentCount
        FROM Comments c
        GROUP BY c.PostId
    ),
    AnswerTiming AS (
        SELECT a.ParentId      AS QuestionId,
               DATEDIFF(second, p.CreationDate, MIN(a.CreationDate)) AS SecondsToFirstAnswer
        FROM Posts a
        JOIN Posts p ON p.Id = a.ParentId
        WHERE a.PostTypeId = 2                      -- answers only
        GROUP BY a.ParentId, p.CreationDate
    ),
    PostDetails AS (
        SELECT t.PostId,
               t.TagName,
               t.OwnerUserId,
               t.CreationDate,
               t.Score,
               vs.UpVotes,
               vs.DownVotes,
               vs.Favorites,
               cs.CommentCount,
               at.SecondsToFirstAnswer,
               CASE WHEN t.AcceptedAnswerId IS NULL THEN 0 ELSE 1 END   AS HasAccepted,
               ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Score DESC, t.CreationDate DESC) AS RankInTag,
               (SELECT COUNT(DISTINCT v2.UserId)
                FROM Votes v2
                WHERE v2.PostId = t.PostId
                AND v2.VoteTypeId = 2)                                     AS UniqueUpVoters
        FROM TagRows t
        LEFT JOIN VoteSums vs ON vs.PostId = t.PostId
        LEFT JOIN CommentStats cs ON cs.PostId = t.PostId
        LEFT JOIN AnswerTiming at ON at.QuestionId = t.PostId
    ),
    TagAggregates AS (
        SELECT
            TagName,
            SUM(Score)                             AS TotalScore,
            COUNT(DISTINCT PostId)                  AS QuestionCount,
            SUM(CASE WHEN AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedCount,
            AVG(ISNULL(SecondsToFirstAnswer,0))     AS AvgFirstAnswerTime
        FROM (
            SELECT t.TagName,
                   qp.PostId,
                   qp.Score,
                   qp.AcceptedAnswerId,
                   at.SecondsToFirstAnswer
            FROM TagRows t
            JOIN QuestionPosts qp ON qp.PostId = t.PostId
            LEFT JOIN AnswerTiming at ON at.QuestionId = qp.PostId
        ) q
        GROUP BY TagName
    )
SELECT
    pd.PostId,
    pd.TagName,
    pd.OwnerUserId,
    pd.CreationDate,
    pd.Score,
    pd.UpVotes,
    pd.DownVotes,
    pd.Favorites,
    pd.CommentCount,
    pd.SecondsToFirstAnswer,
    pd.HasAccepted,
    pd.RankInTag,
    NULL AS TotalScore,
    NULL AS QuestionCount,
    NULL AS AcceptedCount,
    NULL AS AvgFirstAnswerTime,
    pd.UniqueUpVoters
FROM PostDetails pd
UNION ALL
SELECT
    NULL        AS PostId,
    ta.TagName,
    NULL        AS OwnerUserId,
    NULL        AS CreationDate,
    NULL        AS Score,
    NULL        AS UpVotes,
    NULL        AS DownVotes,
    NULL        AS Favorites,
    NULL        AS CommentCount,
    NULL        AS SecondsToFirstAnswer,
    NULL        AS HasAccepted,
    NULL        AS RankInTag,
    ta.TotalScore,
    ta.QuestionCount,
    ta.AcceptedCount,
    ta.AvgFirstAnswerTime,
    NULL        AS UniqueUpVoters
FROM TagAggregates ta
ORDER BY TagName, PostId NULLS LAST
LIMIT 2000;
