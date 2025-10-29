-- {"query": "4091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 943}
WITH QuestionDetails AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        p.OwnerUserId AS OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        COUNT(a.Id) AS AnswerCount,
        SUM(CASE WHEN cv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN cv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNumQ
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Votes cv ON p.Id = cv.PostId AND cv.VoteTypeId IN (2, 3)
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.CreationDate, p.OwnerUserId, u.DisplayName
),
AnswerDetails AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.CreationDate AS AnswerCreationDate,
        au.DisplayName AS AnswererDisplayName,
        a.Score AS AnswerScore,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Users au ON a.OwnerUserId = au.Id
    WHERE a.PostTypeId = 2
),
TaggingInfo AS (
    SELECT
        pl.PostId AS QuestionId,
        COUNT(DISTINCT pl.RelatedPostId) AS DuplicateLinkCount,
        MAX(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS HasDuplicateLink
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
),
UserReputation AS (
    SELECT
        Id,
        Reputation,
        DisplayName,
        CreationDate,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM Users
    WHERE Id <> -1
),
RecentQuestionActivity AS (
    SELECT
        Id AS QuestionId,
        LastActivityDate,
        ROW_NUMBER() OVER (ORDER BY LastActivityDate DESC) AS ActivityRank
    FROM Posts
    WHERE PostTypeId = 1 AND LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
)
SELECT
    qd.Title AS QuestionTitle,
    qd.OwnerDisplayName AS QuestionOwner,
    qd.QuestionCreationDate,
    qd.AnswerCount,
    qd.UpVoteCount,
    qd.DownVoteCount,
    ad.AnswererDisplayName AS TopAnswerer,
    ad.AnswerScore AS TopAnswerScore,
    ad.IsAcceptedAnswer,
    ti.DuplicateLinkCount,
    ti.HasDuplicateLink,
    ur.Reputation AS QuestionOwnerReputation,
    ur.ReputationRank,
    rq.LastActivityDate AS RecentActivityDate
FROM QuestionDetails qd
LEFT JOIN AnswerDetails ad ON qd.QuestionId = ad.QuestionId AND ad.AnswerRank = 1
LEFT JOIN TaggingInfo ti ON qd.QuestionId = ti.QuestionId
LEFT JOIN UserReputation ur ON qd.OwnerUserId = ur.Id
LEFT JOIN RecentQuestionActivity rq ON qd.QuestionId = rq.QuestionId
WHERE qd.RowNumQ BETWEEN 1 AND 100
  AND qd.OwnerDisplayName IS NOT NULL
  AND qd.Title LIKE '%SQL%'
  AND qd.QuestionCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
  AND (COALESCE(ti.HasDuplicateLink, 0) = 1 OR qd.AnswerCount > 5)
ORDER BY qd.QuestionCreationDate DESC;