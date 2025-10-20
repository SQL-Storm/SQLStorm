-- {"query": "344.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 24447} 
WITH
  a AS (
    SELECT
      P.Id AS PostId,
      PT.Name AS PostType,
      P.Title,
      P.CreationDate,
      P.LastEditDate,
      P.Score,
      P.ViewCount,
      P.CommentCount,
      COALESCE(Vc.UpVotes, 0) AS UpVotes,
      COALESCE(Vc.DownVotes, 0) AS DownVotes,
      COALESCE(U.Reputation, 0) AS OwnerReputation,
      COALESCE(CNT.TagCount, 0) AS TagCount,
      (SELECT COUNT(*) FROM Comments C WHERE C.PostId = P.Id) AS CommentCountCor,
      CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
      ROW_NUMBER() OVER (ORDER BY P.LastActivityDate DESC NULLS LAST, P.CreationDate DESC) AS rn
    FROM Posts P
    LEFT JOIN Users U ON P.OwnerUserId = U.Id
    LEFT JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN (
      SELECT PostId, SUM(CASE WHEN VT.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
             SUM(CASE WHEN VT.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
      FROM Votes V
      JOIN VoteTypes VT ON VT.Id = V.VoteTypeId
      GROUP BY PostId
    ) Vc ON Vc.PostId = P.Id
    LEFT JOIN (
      SELECT P2.Id AS pid, COUNT(*) AS TagCount
      FROM Posts P2
      LEFT JOIN LATERAL unnest(string_to_array(substring(P2.Tags, 2, length(P2.Tags) - 2), '><')) AS t(tag) ON TRUE
      GROUP BY P2.Id
    ) CNT ON CNT.pid = P.Id
    WHERE P.PostTypeId = 1
  ),
  b AS (
    SELECT
      P2.Id AS PostId,
      PT2.Name AS PostType,
      P2.Title,
      P2.CreationDate,
      P2.LastEditDate,
      P2.Score,
      P2.ViewCount,
      P2.CommentCount,
      COALESCE(Vc2.UpVotes, 0) AS UpVotes,
      COALESCE(Vc2.DownVotes, 0) AS DownVotes,
      COALESCE(U2.Reputation, 0) AS OwnerReputation,
      COALESCE(CNT2.TagCount, 0) AS TagCount,
      (SELECT COUNT(*) FROM Comments C WHERE C.PostId = P2.Id) AS CommentCountCor,
      CASE WHEN P2.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
      ROW_NUMBER() OVER (ORDER BY P2.LastActivityDate DESC NULLS LAST, P2.CreationDate DESC) AS rn
    FROM Posts P2
    LEFT JOIN Users U2 ON P2.OwnerUserId = U2.Id
    LEFT JOIN PostTypes PT2 ON P2.PostTypeId = PT2.Id
    LEFT JOIN (
      SELECT PostId, SUM(CASE WHEN VT.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
             SUM(CASE WHEN VT.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
      FROM Votes V
      JOIN VoteTypes VT ON VT.Id = V.VoteTypeId
      GROUP BY PostId
    ) Vc2 ON Vc2.PostId = P2.Id
    LEFT JOIN (
      SELECT P3.Id AS pid, COUNT(*) AS TagCount
      FROM Posts P3
      LEFT JOIN LATERAL unnest(string_to_array(substring(P3.Tags, 2, length(P3.Tags) - 2), '><')) AS t(tag) ON TRUE
      GROUP BY P3.Id
    ) CNT2 ON CNT2.pid = P2.Id
    WHERE P2.PostTypeId = 1
  )
SELECT
  PostId, PostType, Title, CreationDate, LastEditDate, Score, ViewCount, CommentCount, UpVotes, DownVotes, OwnerReputation, TagCount, CommentCountCor, HasAcceptedAnswer
FROM a
UNION ALL
SELECT
  PostId, PostType, Title, CreationDate, LastEditDate, Score, ViewCount, CommentCount, UpVotes, DownVotes, OwnerReputation, TagCount, CommentCountCor, HasAcceptedAnswer
FROM b
ORDER BY Score DESC, ViewCount DESC
LIMIT 200;