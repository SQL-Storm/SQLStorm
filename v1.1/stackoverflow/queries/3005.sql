WITH AnswerStats AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount,
        MAX(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS HasUpvote,
        MAX(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS HasDownvote,
        SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
),
QuestionInfo AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.FavoriteCount,
        q.ClosedDate,
        u.DisplayName AS OwnerName,
        u.Reputation,
        u.Location
    FROM Posts q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
),
QuestionAnswers AS (
    SELECT
        a.ParentId AS QuestionId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        a.OwnerUserId AS AnswerOwnerId,
        a.ParentId
    FROM Posts a
    WHERE a.PostTypeId = 2
),
MergedData AS (
    SELECT
        qi.QuestionId,
        qi.Title,
        qi.Tags,
        qi.CreationDate,
        qi.OwnerName,
        qi.Reputation,
        qi.Location,
        qi.Score AS QuestionScore,
        qi.ViewCount,
        qAnswers.AnswerId,
        qAnswers.AnswerScore,
        qAnswers.AnswerCreationDate,
        qAnswers.AnswerOwnerId,
        COALESCE(ats.CommentCount, 0) AS CommentCount,
        COALESCE(ats.HasUpvote, 0) AS HasUpvote,
        COALESCE(ats.HasDownvote, 0) AS HasDownvote,
        COALESCE(ats.TotalVotes, 0) AS TotalVotes,
        aw.AnswerOwnerName,
        aw.AnswererReputation
    FROM QuestionInfo qi
    LEFT JOIN QuestionAnswers qAnswers ON qi.QuestionId = qAnswers.QuestionId
    LEFT JOIN (
        SELECT
            p.Id AS PostId,
            u1.DisplayName AS AnswerOwnerName,
            u1.Reputation AS AnswererReputation
        FROM Posts p
        LEFT JOIN Users u1 ON p.OwnerUserId = u1.Id
        WHERE p.PostTypeId = 2
    ) aw ON qAnswers.AnswerId = aw.PostId
    LEFT JOIN AnswerStats ats ON qAnswers.AnswerId = ats.PostId
),
ComplexPredicate AS (
    SELECT
        QuestionId,
        Title,
        Tags,
        CreationDate,
        OwnerName,
        Reputation,
        Location,
        QuestionScore,
        ViewCount,
        AnswerId,
        AnswerScore,
        AnswerCreationDate,
        AnswerOwnerId,
        CommentCount,
        HasUpvote,
        HasDownvote,
        TotalVotes,
        AnswerOwnerName,
        AnswererReputation
    FROM MergedData
    WHERE
        (
            (Reputation > 1000 AND TotalVotes > 10)
            OR
            (Location IS NULL AND HasUpvote = 1)
        )
        AND
        (CommentCount >= 5 OR (AnswerScore IS NOT NULL AND AnswerScore > 5))
),
FinalSelection AS (
    SELECT DISTINCT
        QuestionId,
        Title,
        OwnerName,
        Reputation,
        Location,
        QuestionScore,
        ViewCount,
        AnswerId,
        AnswerScore,
        AnswerCreationDate,
        AnswerOwnerName,
        AnswererReputation,
        CommentCount,
        HasUpvote,
        HasDownvote,
        TotalVotes
    FROM ComplexPredicate
)
SELECT
    fs.QuestionId,
    fs.Title,
    fs.OwnerName,
    fs.Reputation,
    fs.Location,
    fs.QuestionScore,
    fs.ViewCount,
    fs.AnswerId,
    fs.AnswerScore,
    fs.AnswerCreationDate,
    fs.AnswerOwnerName,
    fs.AnswererReputation,
    fs.CommentCount,
    fs.HasUpvote,
    fs.HasDownvote,
    fs.TotalVotes
FROM FinalSelection fs
LEFT JOIN PostLinks pl ON fs.QuestionId = pl.PostId AND pl.LinkTypeId = 3
WHERE pl.RelatedPostId IS NULL
ORDER BY fs.Reputation DESC, fs.CommentCount DESC;