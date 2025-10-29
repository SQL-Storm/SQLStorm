-- {"query": "2975.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1559} 

WITH RecursiveBadgeScores AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class,
        u.Reputation,
        u.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC, b.Class ASC) AS BadgeRank
    FROM Badges b
    JOIN Users u ON u.Id = b.UserId
    WHERE b.Class IN (1, 2, 3)
),
TopUserBadges AS (
    SELECT UserId, BadgeName, Class, Reputation, CreationDate
    FROM RecursiveBadgeScores
    WHERE BadgeRank <= 5
),
PostVotesSummary AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS AcceptedVotes
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.OwnerUserId AS QuestionOwner,
        q.Score AS QuestionScore,
        q.AnswerCount,
        q.ViewCount,
        pvs.PostId AS AcceptedAnswerId,
        a.OwnerUserId AS AnswerOwner,
        a.Score AS AnswerScore,
        pvs.UpVotes AS AnswerUpVotes,
        pvs.DownVotes AS AnswerDownVotes,
        -- Calculate tag count by counting occurrences of '><' in Tags +1, handling NULL
        CASE WHEN q.Tags IS NULL THEN 0
             ELSE LENGTH(q.Tags) - LENGTH(REPLACE(q.Tags, '><', '')) + 1 END AS TagCount
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
    LEFT JOIN PostVotesSummary pvs ON pvs.PostId = q.AcceptedAnswerId
    WHERE q.PostTypeId = 1
),
UserCommentActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT c.PostId) AS DistinctPostsCommented,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
RecentPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.UserId,
        ph.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13) -- Closed, Reopened, Deleted, Undeleted
),
PostsWithLastHistory AS (
    SELECT
        rph.PostId,
        rph.HistoryTypeName,
        rph.UserId,
        rph.CreationDate AS LastHistoryDate
    FROM RecentPostHistory rph
    WHERE rph.rn = 1
),
DuplicatedPosts AS (
    SELECT DISTINCT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Name = 'Duplicate'
),
AggregatedUserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(p.Score),0) AS TotalPostScore,
        COUNT(p.Id) AS TotalPosts,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END),0) AS QuestionsCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END),0) AS AnswersCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        COALESCE(SUM(v.BountyAmount),0) AS TotalBountyEarned
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (8,9) -- BountyStart, BountyClose
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
    qas.QuestionId,
    qas.Title,
    qas.Tags,
    qas.TagCount,
    qas.OwnerUserId AS QuestionOwnerId,
    u.DisplayName AS QuestionOwnerName,
    u.Reputation AS QuestionOwnerReputation,
    qas.AnswerCount,
    qas.ViewCount,
    qas.QuestionScore,
    qas.AcceptedAnswerId,
    a.OwnerUserId AS AcceptedAnswerOwnerId,
    u2.DisplayName AS AcceptedAnswerOwnerName,
    qas.AnswerScore,
    qas.AnswerUpVotes,
    qas.AnswerDownVotes,
    uc.CommentCount,
    uc.DistinctPostsCommented,
    uc.AvgCommentScore,
    ph.LastHistoryDate,
    ph.HistoryTypeName,
    dup.RelatedPostId AS DuplicateOfPostId,
    dup.LinkTypeName AS DuplicateLinkType,
    -- Complex calculation mixing string, null logic, arithmetic and window functions
    CONCAT(
        'Tags: ', COALESCE(qas.Tags, '<none>'),
        ' | ScoreDiff: ', COALESCE(CAST(qas.QuestionScore - qas.AnswerScore AS VARCHAR), 'N/A'),
        ' | OwnerGapDays: ',
        COALESCE(CAST(
            EXTRACT(DAY FROM (MAX(u.CreationDate) OVER () - MIN(u2.CreationDate) OVER ())) AS VARCHAR
        ), '0'),
        ' | CommentsRatio: ',
        CASE WHEN qas.AnswerCount > 0 THEN 
            CAST(uc.CommentCount * 1.0 / qas.AnswerCount AS VARCHAR)
        ELSE '0' END
    ) AS ComplexSummary
FROM QuestionAnswerStats qas
LEFT JOIN Users u ON u.Id = qas.QuestionOwner
LEFT JOIN Users u2 ON u2.Id = qas.AnswerOwner
LEFT JOIN UserCommentActivity uc ON uc.UserId = qas.QuestionOwner
LEFT JOIN PostsWithLastHistory ph ON ph.PostId = qas.QuestionId
LEFT JOIN DuplicatedPosts dup ON dup.PostId = qas.QuestionId
LEFT JOIN Posts a ON a.Id = qas.AcceptedAnswerId
WHERE qas.AnswerCount > 0
  AND (ph.HistoryTypeName IS NULL OR ph.HistoryTypeName != 'Post Closed')
ORDER BY qas.ViewCount DESC, qas.AnswerCount DESC
LIMIT 100;
