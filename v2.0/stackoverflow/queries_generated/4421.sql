-- {"query": "4421.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1374} 
WITH PostScores AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        COALESCE(pt.Name, 'Unknown') AS PostTypeName,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsClosed,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(ps.CreationDate) AS LastPostCreationDate,
        AVG(ps.Score) AS AveragePostScore,
        SUM(ps.ViewCount) AS TotalViewCount,
        SUM(ps.AnswerCount) FILTER (WHERE ps.PostTypeId = 1) AS QuestionAnswerCount,
        AVG(ps.FavoriteCount) FILTER (WHERE ps.PostTypeId = 1) AS AverageQuestionFavoriteCount
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN PostScores ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
LaggedScores AS (
    SELECT
        PostId,
        OwnerUserId,
        Score,
        CreationDate,
        LAG(Score, 1, 0) OVER (PARTITION BY OwnerUserId ORDER BY CreationDate) AS PreviousScore
    FROM PostScores
    WHERE PostTypeId = 1
),
ClosedQuestionReasons AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN crt.Name IS NULL THEN 'Unknown' ELSE crt.Name END) AS CloseReasonName,
        COUNT(ph.Id) AS CloseVoteCount
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS int) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.PostHistoryCount,
    ua.CommentCount,
    ua.VoteCount,
    ua.UpVotes,
    ua.DownVotes,
    ua.LastPostCreationDate,
    ua.AveragePostScore,
    ua.TotalViewCount,
    ua.QuestionAnswerCount,
    ua.AverageQuestionFavoriteCount,
    COUNT(ps.PostId) FILTER (WHERE ps.PostTypeName = 'Question') AS TotalQuestions,
    SUM(ps.Score) FILTER (WHERE ps.PostTypeName = 'Question') AS TotalQuestionScore,
    AVG(ps.Score) FILTER (WHERE ps.PostTypeName = 'Question') AS AvgQuestionScore,
    COUNT(ps.PostId) FILTER (WHERE ps.PostTypeName = 'Answer') AS TotalAnswers,
    SUM(ps.Score) FILTER (WHERE ps.PostTypeName = 'Answer') AS TotalAnswerScore,
    AVG(ps.Score) FILTER (WHERE ps.PostTypeName = 'Answer') AS AvgAnswerScore,
    COUNT(ls.PostId) FILTER (WHERE ls.Score > ls.PreviousScore) AS QuestionsWithScoreIncrease,
    COALESCE(SUM(CASE WHEN cqr.CloseVoteCount > 0 THEN 1 ELSE 0 END), 0) AS NumberOfClosedQuestions,
    MAX(CASE WHEN cqr.CloseVoteCount > 0 THEN cqr.CloseReasonName ELSE NULL END) AS MostFrequentCloseReason,
    AVG(ps.PostRank) AS AveragePostRank,
    SUM(CASE WHEN ps.IsClosed = 1 THEN 1 ELSE 0 END) AS TotalClosedPosts,
    STRING_AGG(DISTINCT ps.PostTypeName, ', ') AS PostTypesCreated,
    CASE
        WHEN ua.Reputation > 100000 THEN 'High'
        WHEN ua.Reputation > 10000 THEN 'Medium'
        ELSE 'Low'
    END AS ReputationLevel,
    ua.DisplayName || ' (' || ua.UserId || ')' AS DisplayInfo
FROM UserActivity ua
LEFT JOIN PostScores ps ON ua.UserId = ps.OwnerUserId
LEFT JOIN LaggedScores ls ON ua.UserId = ls.OwnerUserId
LEFT JOIN ClosedQuestionReasons cqr ON ua.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = cqr.PostId)
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.PostHistoryCount,
    ua.CommentCount,
    ua.VoteCount,
    ua.UpVotes,
    ua.DownVotes,
    ua.LastPostCreationDate,
    ua.AveragePostScore,
    ua.TotalViewCount,
    ua.QuestionAnswerCount,
    ua.AverageQuestionFavoriteCount
HAVING ua.Reputation > 0 AND ua.UserCreationDate < NOW() - INTERVAL '1 year'
ORDER BY ua.Reputation DESC, ua.UserCreationDate ASC
LIMIT 100;