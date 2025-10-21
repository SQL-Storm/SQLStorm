WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, 
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Users u
    JOIN Votes v ON u.Id = v.UserId
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY u.Id, u.DisplayName
),
QuestionPostHistory AS (
    SELECT p.Id, ph.PostHistoryTypeId, ph.CreationDate, ph.Comment
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13)
),
AnswerPostHistory AS (
    SELECT p.Id, ph.PostHistoryTypeId, ph.CreationDate, ph.Comment
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13) AND p.PostTypeId = 2
),
TopQuestionPosts AS (
    SELECT p.Id, p.Score, p.ViewCount, p.Title
    FROM Posts p
    JOIN QuestionPostHistory qph ON p.Id = qph.Id
    GROUP BY p.Id, p.Score, p.ViewCount, p.Title
    ORDER BY p.Score DESC
    LIMIT 100
),
TopAnswerPosts AS (
    SELECT p.Id, p.Score, p.ViewCount, p.Title
    FROM Posts p
    JOIN AnswerPostHistory aph ON p.Id = aph.Id
    GROUP BY p.Id, p.Score, p.ViewCount, p.Title
    ORDER BY p.Score DESC
    LIMIT 100
)
SELECT 
    tu.Id AS TopUserId, 
    tu.DisplayName AS TopUserName, 
    tu.UpVotes, 
    tu.DownVotes, 
    tp.Id AS TopQuestionPostId, 
    tp.Score AS TopQuestionPostScore, 
    tp.ViewCount AS TopQuestionPostViewCount, 
    tp.Title AS TopQuestionPostTitle, 
    ta.Id AS TopAnswerPostId, 
    ta.Score AS TopAnswerPostScore, 
    ta.ViewCount AS TopAnswerPostViewCount, 
    ta.Title AS TopAnswerPostTitle
FROM TopUsers tu
JOIN TopQuestionPosts tp ON tu.Id = tp.Id
JOIN TopAnswerPosts ta ON tu.Id = ta.Id;