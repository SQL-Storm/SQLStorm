-- {"query": "26061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 864} 

WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
           COUNT(DISTINCT p.Id) AS PostsCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id, u.DisplayName
    HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
QuestionPosts AS (
    SELECT p.Id, p.Score, p.ViewCount, p.Title, p.Tags,
           ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS ScoreRank,
           ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewCountRank
    FROM Posts p
    WHERE p.PostTypeId = 1
),
AnswerPosts AS (
    SELECT p.Id, p.Score, p.ViewCount, p.Title, p.Tags,
           ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS ScoreRank,
           ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewCountRank
    FROM Posts p
    WHERE p.PostTypeId = 2
),
PostHistoryTypesCTE AS (
    SELECT Id, Name
    FROM PostHistoryTypes
    WHERE Id IN (10, 11, 12, 13, 14, 15, 19, 20, 35)
),
CloseReasonTypesCTE AS (
    SELECT Id, Name
    FROM CloseReasonTypes
    WHERE Id IN (101, 102, 103, 104, 105)
)
SELECT 
    u.Id, u.DisplayName, u.Reputation, 
    COALESCE(tu.UpVotes, 0) AS UpVotes, COALESCE(tu.DownVotes, 0) AS DownVotes,
    COALESCE(qp.ScoreRank, 0) AS QuestionScoreRank, COALESCE(ap.ScoreRank, 0) AS AnswerScoreRank,
    COALESCE(qp.ViewCountRank, 0) AS QuestionViewCountRank, COALESCE(ap.ViewCountRank, 0) AS AnswerViewCountRank,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedCount,
    SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenedCount,
    SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeletedCount,
    SUM(CASE WHEN ph.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS UndeletedCount,
    SUM(CASE WHEN crt.Id = 101 THEN 1 ELSE 0 END) AS DuplicateCloseCount,
    SUM(CASE WHEN crt.Id = 102 THEN 1 ELSE 0 END) AS OffTopicCloseCount,
    SUM(CASE WHEN crt.Id = 103 THEN 1 ELSE 0 END) AS NeedsDetailsCloseCount,
    SUM(CASE WHEN crt.Id = 104 THEN 1 ELSE 0 END) AS NeedsMoreFocusCloseCount,
    SUM(CASE WHEN crt.Id = 105 THEN 1 ELSE 0 END) AS OpinionBasedCloseCount
FROM Users u
LEFT JOIN TopUsers tu ON u.Id = tu.Id
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN QuestionPosts qp ON p.Id = qp.Id
LEFT JOIN AnswerPosts ap ON p.Id = ap.Id
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostHistoryTypesCTE pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN CloseReasonTypesCTE crt ON ph.Comment = crt.Id::text
WHERE u.Reputation > 1000
GROUP BY u.Id, u.DisplayName, u.Reputation, tu.UpVotes, tu.DownVotes, qp.ScoreRank, ap.ScoreRank, qp.ViewCountRank, ap.ViewCountRank
ORDER BY u.Reputation DESC;
