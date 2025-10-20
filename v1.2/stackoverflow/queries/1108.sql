WITH RECURSIVE RecursivePostRelations AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        0 AS Depth
    FROM Posts p
    WHERE p.PostTypeId = 1 -- questions only
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    UNION ALL
    SELECT 
        c.Id,
        c.PostTypeId,
        c.AcceptedAnswerId,
        c.ParentId,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.OwnerUserId,
        c.Title,
        c.Tags,
        rpr.Depth + 1
    FROM Posts c
    INNER JOIN RecursivePostRelations rpr ON c.ParentId = rpr.Id
),
UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COALESCE(AVG(EXTRACT(EPOCH FROM (b.Date - u.CreationDate))/86400),0) AS AvgBadgeDaysAfterJoin
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostVoteSummaries AS (
    SELECT 
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
        COUNT(v.Id) AS TotalVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
),
TopAnswerers AS (
    SELECT 
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        u.DisplayName,
        COUNT(*) AS AnswerCount,
        SUM(a.Score) AS TotalScore,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY SUM(a.Score) DESC) AS ScoreRank
    FROM Posts a
    INNER JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2 -- answers
    GROUP BY a.ParentId, a.OwnerUserId, u.DisplayName
),
QuestionCloseHistory AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS CloseDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS ReopenDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS LastClosePHId,
        ph.Comment AS CloseReasonCode
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10,11)
    GROUP BY ph.PostId, ph.Comment
),
LatestCommentPerPost AS (
    SELECT DISTINCT ON (c.PostId)
        c.PostId,
        c.Text AS LatestCommentText,
        c.CreationDate AS LatestCommentDate,
        c.UserDisplayName AS LatestCommentUser
    FROM Comments c
    ORDER BY c.PostId, c.CreationDate DESC
),
TagSplit AS (
    SELECT 
        p.Id AS PostId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagQuestionCounts AS (
    SELECT 
        ts.TagName,
        COUNT(DISTINCT ts.PostId) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore
    FROM TagSplit ts
    JOIN Posts p ON p.Id = ts.PostId
    GROUP BY ts.TagName
),
DuplicateLinks AS (
    SELECT pl.PostId, COUNT(pl.Id) AS DuplicateCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
),
UserActivityWindows AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COUNT(c.Id) AS CommentsWritten,
        COUNT(v.Id) AS VotesCast,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate,
        
        -- Window aggregates for reputation and up/down votes over the last year
        SUM(u.Reputation) OVER () as TotalReputation,
        SUM(u.UpVotes) OVER () AS TotalUpVotes,
        SUM(u.DownVotes) OVER () AS TotalDownVotes
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
)
SELECT 
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    u.DisplayName AS QuestionOwner,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    pv.UpVotes,
    pv.DownVotes,
    pv.Favorites,
    dup.DuplicateCount,
    
    COALESCE(tc.QuestionCount,0) AS TagQuestionCount,
    COALESCE(tc.AvgQuestionScore,0) AS TagAvgScore,
    
    qc.CloseDate,
    qc.ReopenDate,
    qc.CloseReasonCode,
    
    la.LatestCommentText,
    la.LatestCommentDate,
    la.LatestCommentUser,
    
    ta.AnswerCount,
    ta.TotalScore,
    ta.ScoreRank,
    
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.CommentsWritten,
    ua.VotesCast,
    
    CASE 
        WHEN q.ViewCount > 0 THEN ROUND((CAST(pv.UpVotes AS numeric) - CAST(pv.DownVotes AS numeric)) / NULLIF(q.ViewCount,0)::numeric, 5)
        ELSE NULL
    END AS VoteRatioPerView,
    
    CASE 
        WHEN ua.AnswersPosted > 0 THEN ROUND(ub.AvgBadgeDaysAfterJoin / ua.AnswersPosted, 2)
        ELSE NULL
    END AS AvgBadgeDaysPerAnswer,
    
    CONCAT(
        COALESCE(NULLIF(REPLACE(q.Title, '''', ''''''), ''), '[No Title]'),
        ' [Tags: ', 
        COALESCE(q.Tags, '[No Tags]'),
        ']'
    ) AS TitleWithTags,
    
    CASE 
        WHEN qc.CloseDate IS NOT NULL AND qc.CloseDate = q.CreationDate THEN 'Closed'
        WHEN qc.CloseDate IS NOT NULL AND qc.CloseDate > q.CreationDate THEN 'Recently Closed'
        ELSE 'Open'
    END AS PostStatus
    
FROM RecursivePostRelations q
INNER JOIN Users u ON u.Id = q.OwnerUserId
LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
LEFT JOIN PostVoteSummaries pv ON pv.PostId = q.Id
LEFT JOIN DuplicateLinks dup ON dup.PostId = q.Id
LEFT JOIN TagQuestionCounts tc ON tc.TagName = (
    SELECT unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><')) LIMIT 1
)
LEFT JOIN QuestionCloseHistory qc ON qc.PostId = q.Id
LEFT JOIN LatestCommentPerPost la ON la.PostId = q.Id
LEFT JOIN TopAnswerers ta ON ta.QuestionId = q.Id AND ta.ScoreRank = 1
LEFT JOIN UserActivityWindows ua ON ua.UserId = u.Id

WHERE q.Depth = 0

ORDER BY q.Score DESC NULLS LAST, q.ViewCount DESC NULLS LAST
LIMIT 100;