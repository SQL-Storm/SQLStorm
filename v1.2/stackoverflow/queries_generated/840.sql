-- {"query": "840.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1729} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        p.Id AS ExcerptPostId,
        p.Title AS ExcerptTitle,
        1 AS Level
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.Count > 1000

    UNION ALL

    SELECT 
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.IsModeratorOnly,
        t2.IsRequired,
        p2.Id AS ExcerptPostId,
        p2.Title AS ExcerptTitle,
        r.Level + 1
    FROM Tags t2
    JOIN Posts p2 ON t2.ExcerptPostId = p2.Id
    JOIN RecursiveTagHierarchy r ON t2.Id <> r.Id AND t2.Count BETWEEN r.Count/2 AND r.Count
    WHERE r.Level < 3
),
UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostScoresAndRanks AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsOfType
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers only
),
AcceptedAnswerInfo AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        a.OwnerUserId AS AnswerOwnerUserId,
        u.DisplayName AS AnswerOwnerDisplayName
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS TotalPostScore,
        COUNT(DISTINCT ph.PostId) AS PostEditCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
QuestionCloseAnalysis AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        cht.Name AS CloseReason,
        ph.CreationDate AS CloseDate,
        u.DisplayName AS CloserDisplayName,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 6) AS CloseVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 7) AS ReopenVotes
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 -- Post Closed
    LEFT JOIN CloseReasonTypes cht ON cht.Id = COALESCE(
        NULLIF(CAST(ph.Comment AS int), 0),
        NULL
    )
    LEFT JOIN Users u ON u.Id = ph.UserId
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (6,7)
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
    GROUP BY p.Id, p.Title, p.CreationDate, cht.Name, ph.CreationDate, u.DisplayName
),
CombinedVotesAndComments AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(c.Id) AS CommentCount,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Unknown'), ', ') AS Commenters,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    GROUP BY p.Id, p.PostTypeId
),
FinalSelection AS (
    SELECT 
        uaw.UserId,
        uaw.DisplayName AS UserName,
        uaw.Reputation,
        uaw.QuestionCount,
        uaw.AnswerCount,
        uaw.TotalPostScore,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        p.ScoreRank,
        p.TotalPostsOfType,
        p.Title AS PostTitle,
        p.Tags,
        COALESCE(aa.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        aa.AcceptedAnswerScore,
        aa.AnswerOwnerDisplayName,
        qca.CloseReason,
        qca.CloseVotes,
        qca.ReopenVotes,
        cvc.UpVotes,
        cvc.DownVotes,
        cvc.CommentCount,
        cvc.Commenters,
        cvc.LastCommentDate,
        rth.Level AS TagHierarchyLevel,
        rth.TagName AS RelatedTagName,
        rth.Count AS RelatedTagCount,
        rth.ExcerptTitle AS RelatedTagExcerptTitle
    FROM UserActivityWindow uaw
    LEFT JOIN UserBadgeCounts ubc ON uaw.UserId = ubc.UserId
    LEFT JOIN PostScoresAndRanks p ON p.OwnerUserId = uaw.UserId AND p.ScoreRank <= 5
    LEFT JOIN AcceptedAnswerInfo aa ON aa.QuestionId = p.Id AND p.PostTypeId = 1
    LEFT JOIN QuestionCloseAnalysis qca ON qca.QuestionId = p.Id
    LEFT JOIN CombinedVotesAndComments cvc ON cvc.PostId = p.Id
    LEFT JOIN RecursiveTagHierarchy rth ON rth.TagName = ANY (string_to_array(coalesce(p.Tags, ''), '><'))
    WHERE uaw.Reputation > 1000
),
RankedResults AS (
    SELECT 
        *,
        RANK() OVER (PARTITION BY UserId ORDER BY TotalPostScore DESC) AS UserPostScoreRank,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) AS GlobalReputationRank
    FROM FinalSelection
)
SELECT
    UserId,
    UserName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    QuestionCount,
    AnswerCount,
    TotalPostScore,
    PostTitle,
    Tags,
    AcceptedAnswerId,
    AcceptedAnswerScore,
    AnswerOwnerDisplayName,
    CloseReason,
    CloseVotes,
    ReopenVotes,
    UpVotes,
    DownVotes,
    CommentCount,
    Commenters,
    LastCommentDate,
    RelatedTagName,
    RelatedTagCount,
    RelatedTagExcerptTitle,
    TagHierarchyLevel,
    UserPostScoreRank,
    GlobalReputationRank
FROM RankedResults
WHERE UserPostScoreRank = 1
ORDER BY GlobalReputationRank, UserPostScoreRank, Reputation DESC
LIMIT 100;
