WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(v.CreationDate) AS LastVoteDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.LastAccessDate
),
HighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        LastAccessDate,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        QuestionScore,
        AnswerScore,
        LastPostDate,
        LastVoteDate
    FROM
        UserActivity
    WHERE
        Reputation > 1000
),
ActiveHighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        LastAccessDate,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        QuestionScore,
        AnswerScore,
        LastPostDate,
        LastVoteDate
    FROM
        HighReputationUsers
    WHERE
        LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
),
UserPosts AS (
  SELECT
    p.*
  FROM
    Posts p
  JOIN
    ActiveHighReputationUsers u ON p.OwnerUserId = u.UserId
),
RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostType,
        u.DisplayName AS OwnerDisplayName,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        COALESCE(p.ParentId, 0) AS ParentId
    FROM
        UserPosts p
   JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7' DAY)
),
HighActivityPosts AS (
    SELECT
        PostId,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount,
        Title,
        OwnerUserId,
        OwnerDisplayName,
        PostType,
        Tags,
        AnswerCount,
        CommentCount,
        AcceptedAnswerId,
        ParentId
    FROM
        RecentPosts
    WHERE
        Score > 5 OR ViewCount > 500
),
VotesInfo AS (
    SELECT
        v.PostId,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS TotalBountyAmount
    FROM
        Votes v
    WHERE
        v.PostId IN (SELECT PostId FROM HighActivityPosts)
    GROUP BY
        v.PostId
),
CommentsInfo AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalComments,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
       Comments c
    WHERE
        c.PostId IN (SELECT PostId FROM HighActivityPosts)
    GROUP BY
        c.PostId
),
PostHistoryInfo AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryRecords,
        MAX(ph.CreationDate) AS LastEditDate
    FROM
        PostHistory ph
    WHERE
        ph.PostId IN (SELECT PostId FROM HighActivityPosts)
    GROUP BY
        ph.PostId
),
FinalPostData AS (
SELECT
    hp.PostId,
    hp.PostTypeId,
    hp.CreationDate,
    hp.Score,
    hp.ViewCount,
    hp.Title,
    hp.OwnerUserId,
    hp.OwnerDisplayName,
    hp.PostType,
    hp.Tags,
    hp.AnswerCount,
    hp.CommentCount,
    hp.AcceptedAnswerId,
    COALESCE(v.TotalVotes, 0) AS TotalVotes,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(v.TotalBountyAmount, 0) AS TotalBountyAmount,
    COALESCE(c.TotalComments, 0) AS TotalComments,
    COALESCE(c.LastCommentDate, TIMESTAMP '1970-01-01 00:00:00') AS LastCommentDate,
    COALESCE(ph.TotalHistoryRecords, 0) AS TotalHistoryRecords,
    COALESCE(ph.LastEditDate, TIMESTAMP '1970-01-01 00:00:00') AS LastEditDate
FROM
    HighActivityPosts hp
LEFT JOIN
    VotesInfo v ON hp.PostId = v.PostId
LEFT JOIN
    CommentsInfo c ON hp.PostId = c.PostId
LEFT JOIN
    PostHistoryInfo ph ON hp.PostId = ph.PostId
)
SELECT
    fpd.PostId,
    fpd.PostTypeId,
    fpd.CreationDate,
    fpd.Score,
    fpd.ViewCount,
    fpd.Title,
    fpd.PostType,
    fpd.Tags,
    fpd.OwnerUserId,
    fpd.OwnerDisplayName,
    fpd.AnswerCount,
    fpd.CommentCount,
    fpd.TotalVotes,
    fpd.UpVotes,
    fpd.DownVotes,
    fpd.TotalBountyAmount,
    fpd.TotalComments,
    fpd.LastCommentDate,
    fpd.TotalHistoryRecords,
    fpd.LastEditDate,
    fpd.AcceptedAnswerId,
    COALESCE(p2.Title, 'No Accepted Answer') AS AcceptedAnswerTitle
FROM
    FinalPostData fpd
LEFT JOIN Posts p2 ON fpd.AcceptedAnswerId = p2.Id
ORDER BY
    fpd.Score DESC, fpd.ViewCount DESC
LIMIT
    100;