-- {"query": "4756.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 959} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.UserDisplayName,
        ph.CreationDate AS EditDate,
        pht.Name AS EditType,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Title, Body, Tags edits and rollbacks
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        SUM(CASE WHEN p.AnswerCount IS NOT NULL THEN p.AnswerCount ELSE 0 END) AS TotalAnsweredQuestions
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
HighReputationUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        upa.TotalPosts,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.AverageScore,
        upa.TotalAnsweredQuestions
    FROM Users u
    LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
    WHERE u.Reputation > 100000
),
TopRatedAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        p.Score,
        ROW_NUMBER() OVER(PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) as rn
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.Score > 100
)
SELECT
    hru.DisplayName AS UserDisplayName,
    hru.Reputation,
    hru.TotalPosts,
    hru.QuestionCount,
    hru.AnswerCount,
    hru.AverageScore,
    hru.TotalAnsweredQuestions,
    COUNT(DISTINCT rpe.PostId) AS DistinctEditedPosts,
    SUM(CASE WHEN rpe.EditType LIKE '%Title%' THEN 1 ELSE 0 END) AS TitleEdits,
    SUM(CASE WHEN rpe.EditType LIKE '%Body%' THEN 1 ELSE 0 END) AS BodyEdits,
    SUM(CASE WHEN rpe.EditType LIKE '%Tags%' THEN 1 ELSE 0 END) AS TagEdits,
    COUNT(DISTINCT pra.AnswerId) AS DistinctTopAnswersWritten,
    COALESCE(SUM(pra.Score), 0) AS TotalScoreOfTopAnswers
FROM HighReputationUsers hru
LEFT JOIN RankedPostEdits rpe ON hru.Id = rpe.UserId AND rpe.rn = 1
LEFT JOIN TopRatedAnswers pra ON hru.Id = pra.OwnerUserId
WHERE hru.DisplayName IS NOT NULL
  AND LENGTH(hru.DisplayName) > 3
  AND (hru.UpVotes - hru.DownVotes) > 1000
GROUP BY
    hru.Id,
    hru.DisplayName,
    hru.Reputation,
    hru.TotalPosts,
    hru.QuestionCount,
    hru.AnswerCount,
    hru.AverageScore,
    hru.TotalAnsweredQuestions
HAVING COUNT(DISTINCT rpe.PostId) > 5 OR COUNT(DISTINCT pra.AnswerId) > 10
ORDER BY
    hru.Reputation DESC,
    hru.TotalPosts DESC,
    COALESCE(SUM(pra.Score), 0) DESC
LIMIT 100;