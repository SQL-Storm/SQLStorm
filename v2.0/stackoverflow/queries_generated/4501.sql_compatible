WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserPostCounts AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
PostLaggedScore AS (
    SELECT
        p.Id,
        p.Score,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousDayScore
    FROM Posts p
    WHERE p.PostTypeId = 1
),
RecentQuestions AS (
    SELECT
        Id,
        Title,
        OwnerUserId,
        CreationDate
    FROM Posts
    WHERE PostTypeId = 1
      AND CreationDate >= (cast('2024-10-01' as date) - INTERVAL '30' DAY)
),
TopUsersByQuestions AS (
    SELECT
        upc.OwnerUserId,
        u.DisplayName,
        upc.QuestionCount,
        ROW_NUMBER() OVER (ORDER BY upc.QuestionCount DESC, u.Reputation DESC) AS UserRank
    FROM UserPostCounts upc
    JOIN Users u ON upc.OwnerUserId = u.Id
    WHERE upc.QuestionCount > 100
),
PostScoreChange AS (
    SELECT
        pls.Id,
        (pls.Score - pls.PreviousDayScore) AS ScoreChange
    FROM PostLaggedScore pls
    WHERE (pls.Score - pls.PreviousDayScore) > 10
)
SELECT
    rq.Id,
    rq.Title AS QuestionTitle,
    rq.OwnerUserId,
    rq.CreationDate,
    tuq.DisplayName AS TopUserDisplayName,
    tuq.UserRank,
    COALESCE(psc.ScoreChange, 0) AS SignificantScoreIncrease,
    CASE
        WHEN rq.CreationDate < (cast('2024-10-01' as date) - INTERVAL '7' DAY) THEN 'OlderThanAWeek'
        WHEN rq.CreationDate < (cast('2024-10-01' as date) - INTERVAL '1' DAY) THEN 'BetweenADayAndAWeek'
        ELSE 'WithinTheLastDay'
    END AS AgeCategory,
    COUNT(c.Id) AS CommentCountOnQuestion,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
FROM RecentQuestions rq
LEFT JOIN TopUsersByQuestions tuq ON rq.OwnerUserId = tuq.OwnerUserId
LEFT JOIN PostScoreChange psc ON rq.Id = psc.Id
LEFT JOIN Comments c ON rq.Id = c.PostId
LEFT JOIN Votes v ON rq.Id = v.PostId
WHERE (tuq.UserRank IS NULL OR tuq.UserRank <= 50)
  AND EXISTS (
    SELECT 1
    FROM RankedPostEdits rpe
    WHERE rpe.PostId = rq.Id
      AND rpe.rn = 1
      AND rpe.UserId <> rq.OwnerUserId
)
GROUP BY
    rq.Id,
    rq.Title,
    rq.OwnerUserId,
    rq.CreationDate,
    tuq.DisplayName,
    tuq.UserRank,
    COALESCE(psc.ScoreChange, 0),
    CASE
        WHEN rq.CreationDate < (cast('2024-10-01' as date) - INTERVAL '7' DAY) THEN 'OlderThanAWeek'
        WHEN rq.CreationDate < (cast('2024-10-01' as date) - INTERVAL '1' DAY) THEN 'BetweenADayAndAWeek'
        ELSE 'WithinTheLastDay'
    END
HAVING COUNT(c.Id) > 5 OR SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 20
ORDER BY
    tuq.UserRank ASC NULLS LAST,
    SignificantScoreIncrease DESC,
    AgeCategory;