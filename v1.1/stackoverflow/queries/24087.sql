WITH
    SqlQuestions AS (
        SELECT
            p.Id,
            p.OwnerUserId,
            p.Title,
            p.Score,
            p.CreationDate,
            p.Tags,
            p.LastActivityDate,
            p.AnswerCount,
            p.PostTypeId
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags LIKE '%<sql>%'
    ),

    VoteAgg AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
            SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes
        FROM Votes v
        GROUP BY v.PostId
    ),

    LatestComment AS (
        SELECT
            c.PostId,
            MAX(c.CreationDate) AS LastCommented
        FROM Comments c
        GROUP BY c.PostId
    ),

    UserSummary AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
            COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
            AVG(p.Score)                                      AS AvgScore,
            RANK() OVER (PARTITION BY u.Reputation
                         ORDER BY COUNT(p.Id) DESC)         AS Rank
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    TopBottomUsers AS (
        SELECT Id, DisplayName, Reputation, QuestionCount, Rank
        FROM UserSummary
        WHERE QuestionCount > 20

        UNION ALL

        SELECT Id, DisplayName, Reputation, QuestionCount, Rank
        FROM UserSummary
        WHERE QuestionCount < 5
    )

SELECT
    tbu.Id                      AS UserId,
    tbu.DisplayName             AS UserName,
    tbu.Reputation,
    sq.Id                       AS PostId,
    sq.Title,
    sq.Score,
    va.UpVotes,
    va.DownVotes,
    va.AcceptedVotes,
    lc.LastCommented,
    (SELECT COUNT(*) FROM Posts a
     WHERE a.ParentId = sq.Id
       AND a.PostTypeId = 2)     AS NumAnswers,
    CASE
        WHEN sq.Score < 0 THEN 'Low'
        WHEN sq.Score BETWEEN 0 AND 5 THEN 'Medium'
        ELSE 'High'
    END                         AS ScoreBand,
    tbu.Rank,
    sq.CreationDate,
    sq.AnswerCount
FROM TopBottomUsers tbu
JOIN SqlQuestions sq ON sq.OwnerUserId = tbu.Id
LEFT JOIN VoteAgg va ON va.PostId = sq.Id
LEFT JOIN LatestComment lc ON lc.PostId = sq.Id
WHERE (tbu.Reputation IS NOT NULL OR tbu.Reputation IS NULL)
  AND (sq.AnswerCount IS NULL OR sq.AnswerCount > 0)
GROUP BY
    tbu.Id,
    tbu.DisplayName,
    tbu.Reputation,
    tbu.Rank,
    sq.Id,
    sq.Title,
    sq.Score,
    va.UpVotes,
    va.DownVotes,
    va.AcceptedVotes,
    lc.LastCommented,
    sq.CreationDate,
    sq.AnswerCount
ORDER BY tbu.Rank ASC,
         va.AcceptedVotes DESC,
         sq.CreationDate DESC
LIMIT 50;