-- {"query": "716.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2300} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id, 
        t.TagName, 
        t.Count, 
        t.ExcerptPostId, 
        t.WikiPostId,
        ARRAY[t.TagName] AS AncestorPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT 
        child.Id, 
        child.TagName, 
        child.Count, 
        child.ExcerptPostId, 
        child.WikiPostId,
        parent.AncestorPath || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy parent ON child.Id <> parent.Id AND POSITION(child.TagName IN ARRAY_TO_STRING(parent.AncestorPath, ',')) = 0
    WHERE child.IsModeratorOnly = 0 AND child.IsRequired = 0
),
UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END), 0) AS TagBasedBadges,
        COALESCE(MAX(b.Date), '1900-01-01'::timestamp) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostScoreWindow AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        COUNT(c.Id) AS CommentCount,
        SUM(COALESCE(v.VoteTypeId = 2::smallint, 0)::int) AS UpVotes,
        SUM(COALESCE(v.VoteTypeId = 3::smallint, 0)::int) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScore,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostRank
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId IN (1,2) -- Questions and Answers only
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags
),
TopUsersByActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.AboutMe,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(COUNT(p.Id), 0) AS PostCount,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        ub.LastBadgeDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 -- Questions only
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.AboutMe, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.LastBadgeDate
    HAVING COUNT(p.Id) > 10
),
QuestionsWithAcceptedAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        a.ViewCount AS AcceptedAnswerViews,
        a.OwnerUserId AS AcceptedAnswerUserId,
        u.DisplayName AS AcceptedAnswerUserName,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL
),
DuplicateQuestions AS (
    SELECT DISTINCT pl.PostId AS DuplicateQuestionId, pl.RelatedPostId AS OriginalQuestionId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3 -- Duplicate link type
),
FilteredQuestions AS (
    SELECT 
        q.QuestionId,
        q.Title,
        q.CreationDate,
        q.QuestionScore,
        q.ViewCount,
        q.Tags,
        q.AcceptedAnswerId,
        q.AcceptedAnswerScore,
        q.AcceptedAnswerViews,
        q.AcceptedAnswerUserId,
        q.AcceptedAnswerUserName,
        dq.OriginalQuestionId
    FROM QuestionsWithAcceptedAnswerStats q
    LEFT JOIN DuplicateQuestions dq ON dq.DuplicateQuestionId = q.QuestionId
    WHERE q.QuestionScore > 5 AND (dq.OriginalQuestionId IS NULL OR dq.OriginalQuestionId <> q.QuestionId)
),
UserRecentBadges AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS BadgeRank
    FROM Badges b
    WHERE b.Date > NOW() - INTERVAL '1 year'
),
UserActivitySummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS CommentsMade,
        COALESCE(COUNT(DISTINCT v.Id), 0) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCast,
        COALESCE(COUNT(DISTINCT v.Id), 0) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCast,
        COALESCE(MAX(b.Date), '1900-01-01'::timestamp) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    fq.QuestionId,
    fq.Title,
    fq.CreationDate AS QuestionCreated,
    fq.QuestionScore,
    fq.ViewCount,
    fq.Tags,
    fq.AcceptedAnswerId,
    fq.AcceptedAnswerScore,
    fq.AcceptedAnswerViews,
    fq.AcceptedAnswerUserId,
    fq.AcceptedAnswerUserName,
    fq.OriginalQuestionId,
    uas.QuestionsPosted,
    uas.AnswersPosted,
    uas.CommentsMade,
    uas.UpVotesCast,
    uas.DownVotesCast,
    uas.LastBadgeDate,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ubc.TagBasedBadges,
    STRING_AGG(DISTINCT ph.Name, ', ') AS PostHistoryEvents,
    MAX(pht.Name) FILTER (WHERE pht.Id IN (10,11)) AS CloseReopenEvent,
    COALESCE(pt.Name, 'Unknown') AS AcceptedAnswerPostType,
    CASE 
        WHEN fq.AcceptedAnswerScore > fq.QuestionScore THEN 'Answer Score Higher'
        WHEN fq.AcceptedAnswerScore = fq.QuestionScore THEN 'Scores Equal'
        ELSE 'Question Score Higher'
    END AS ScoreComparison,
    COUNT(DISTINCT c.Id) AS TotalCommentsOnQuestion,
    MAX(u.LastAccessDate) AS AcceptedAnswerUserLastAccess,
    AVG(vote_counts.UpVotes) OVER (PARTITION BY fq.AcceptedAnswerUserId) AS AvgAnswerUpVotesByUser,
    NTILE(5) OVER (ORDER BY fq.QuestionScore DESC) AS QuestionScoreQuintile,
    CASE WHEN fq.AcceptedAnswerViews IS NULL THEN 0 ELSE fq.AcceptedAnswerViews END AS AcceptedAnswerViewCount,
    CASE WHEN uas.LastBadgeDate > NOW() - INTERVAL '30 days' THEN 1 ELSE 0 END AS HasRecentBadge
FROM FilteredQuestions fq
LEFT JOIN UserActivitySummary uas ON uas.UserId = fq.AcceptedAnswerUserId
LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = fq.AcceptedAnswerUserId
LEFT JOIN PostHistory ph ON ph.PostId = fq.QuestionId
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN Posts pa ON pa.Id = fq.AcceptedAnswerId
LEFT JOIN PostTypes pt ON pt.Id = pa.PostTypeId
LEFT JOIN Comments c ON c.PostId = fq.QuestionId
LEFT JOIN (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    GROUP BY v.PostId
) vote_counts ON vote_counts.PostId = fq.AcceptedAnswerId
LEFT JOIN Users u ON u.Id = fq.AcceptedAnswerUserId
GROUP BY 
    fq.QuestionId, fq.Title, fq.CreationDate, fq.QuestionScore, fq.ViewCount, fq.Tags, fq.AcceptedAnswerId, fq.AcceptedAnswerScore, 
    fq.AcceptedAnswerViews, fq.AcceptedAnswerUserId, fq.AcceptedAnswerUserName, fq.OriginalQuestionId, uas.QuestionsPosted, 
    uas.AnswersPosted, uas.CommentsMade, uas.UpVotesCast, uas.DownVotesCast, uas.LastBadgeDate, ubc.GoldBadges, ubc.SilverBadges, 
    ubc.BronzeBadges, ubc.TagBasedBadges, pt.Name, vote_counts.UpVotes, uas.LastBadgeDate
ORDER BY fq.QuestionScore DESC, fq.ViewCount DESC
LIMIT 100;
