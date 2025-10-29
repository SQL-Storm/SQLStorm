WITH RankedUserPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AverageScore,
        MAX(p.Score) AS MaxScore,
        MIN(CASE WHEN p.Score > 0 THEN p.Score ELSE NULL END) AS MinPositiveScore,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
),
RecentHotQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC, p.ViewCount DESC) AS hot_rank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7' DAY)
      AND p.FavoriteCount > 10
),
HighReputationUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(ups.QuestionCount, 0) AS TotalQuestions,
        COALESCE(ups.AnswerCount, 0) AS TotalAnswers,
        COALESCE(ups.TotalScore, 0) AS TotalPostScore,
        COALESCE(ups.AcceptedAnswersCount, 0) AS TotalAcceptedAnswers
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    WHERE u.Reputation > 50000
),
PostEditFrequency AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.RevisionGUID) AS EditCount,
        MIN(ph.CreationDate) AS FirstEditDate,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.PostId
)
SELECT
    rhq.Title AS HotQuestionTitle,
    rhq.CreationDate AS HotQuestionDate,
    rhq.Score AS HotQuestionScore,
    hr.DisplayName AS HighRepUser,
    hr.Reputation AS UserReputation,
    COALESCE(rup.PostCreationDate, CAST('1900-01-01' AS timestamp)) AS LatestUserPostDate,
    COALESCE(pef.EditCount, 0) AS PostEditCount,
    CASE
        WHEN pef.LastEditDate IS NOT NULL AND pef.FirstEditDate IS NOT NULL AND pef.LastEditDate <> pef.FirstEditDate
        THEN EXTRACT(EPOCH FROM (pef.LastEditDate - pef.FirstEditDate)) / NULLIF(pef.EditCount, 0)
        ELSE 0
    END AS AvgTimeBetweenEditsSeconds,
    COALESCE(p.AnswerCount, 0) AS AnswerCountForHotQuestion,
    COALESCE(c.CommentCount, 0) AS CommentCountForHotQuestion,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rhq.Id AND v.VoteTypeId = 2) AS UpVoteCountForHotQuestion,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rhq.Id AND v.VoteTypeId = 3) AS DownVoteCountForHotQuestion,
    CASE
        WHEN hr.UserCreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365' DAY) AND hr.TotalQuestions > 1000 THEN 'Veteran Contributor'
        WHEN hr.TotalAnswers > 500 AND hr.TotalAcceptedAnswers > 50 THEN 'High Impact Answerer'
        ELSE 'Other'
    END AS UserArchetype,
    rhq.hot_rank
FROM RecentHotQuestions rhq
INNER JOIN Users u ON rhq.OwnerUserId = u.Id
LEFT JOIN HighReputationUsers hr ON u.Id = hr.UserId
LEFT JOIN RankedUserPosts rup ON hr.UserId = rup.OwnerUserId AND rup.rn = 1
LEFT JOIN PostEditFrequency pef ON rhq.Id = pef.PostId
LEFT JOIN Posts p ON rhq.Id = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
) c ON rhq.Id = c.PostId
WHERE hr.Reputation > 100000
GROUP BY
    rhq.Title,
    rhq.CreationDate,
    rhq.Score,
    hr.DisplayName,
    hr.Reputation,
    rup.PostCreationDate,
    pef.EditCount,
    pef.LastEditDate,
    pef.FirstEditDate,
    p.AnswerCount,
    c.CommentCount,
    rhq.Id,
    hr.UserCreationDate,
    hr.TotalQuestions,
    hr.TotalAnswers,
    hr.TotalAcceptedAnswers,
    rhq.hot_rank
ORDER BY rhq.hot_rank, hr.Reputation DESC;