WITH UserQuestionData AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        p.Id AS QuestionId,
        p.Score,
        p.ViewCount,
        p.Tags
    FROM
        Users u
    INNER JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.PostTypeId = 1
),
UserAnswerData AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        p.Id AS AnswerId,
        p.Score,
        p.ParentId AS QuestionId
    FROM
        Users u
    INNER JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.PostTypeId = 2
),
UserVoteData AS (
    SELECT
        u.Id,
        u.DisplayName,
        v.PostId,
        v.VoteTypeId
    FROM
        Users u
    INNER JOIN
        Votes v ON u.Id = v.UserId
    WHERE
        v.VoteTypeId IN (2, 3)
),
TagData AS (
    SELECT
        t.Id,
        t.TagName,
        p.Id AS PostId
    FROM
        Tags t
    INNER JOIN
        Posts p ON t.Id = p.Id
    WHERE
        p.PostTypeId = 1
)
SELECT
    uqd.Id,
    uqd.DisplayName,
    uqd.Reputation,
    uqd.QuestionId,
    uqd.Score,
    uqd.ViewCount,
    uqd.Tags,
    uad.AnswerId,
    uad.Score AS AnswerScore,
    uvd.VoteTypeId,
    td.TagName
FROM
    UserQuestionData AS uqd
LEFT JOIN
    UserAnswerData AS uad ON uqd.QuestionId = uad.QuestionId
LEFT JOIN
    UserVoteData AS uvd ON uqd.Id = uvd.PostId
LEFT JOIN
    TagData AS td ON uqd.QuestionId = td.PostId
WHERE
    uqd.Reputation > 1000
    AND uqd.Score > 10
    AND uad.AnswerId IS NOT NULL
    AND uvd.VoteTypeId IN (2, 3)
    AND td.TagName IS NOT NULL
GROUP BY
    uqd.Id,
    uqd.DisplayName,
    uqd.Reputation,
    uqd.QuestionId,
    uqd.Score,
    uqd.ViewCount,
    uqd.Tags,
    uad.AnswerId,
    uad.Score,
    uvd.VoteTypeId,
    td.TagName
ORDER BY
    uqd.Reputation DESC,
    uqd.Score DESC,
    uad.Score DESC;