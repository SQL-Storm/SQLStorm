-- {"query": "2212.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1720} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath,
        1 AS Depth
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        t.Count,
        rth.TagPath || t.TagName,
        rth.Depth + 1
    FROM Tags t
    JOIN PostLinks pl ON pl.PostId = t.ExcerptPostId
    JOIN Posts p ON p.Id = pl.RelatedPostId AND p.PostTypeId = 1
    JOIN RecursiveTagHierarchy rth ON rth.Id = p.Id
    WHERE rth.Depth < 3
),
UserQuestionStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT q.Id) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        AVG(COALESCE(a.Score,0)) AS AvgAnswerScore,
        SUM(COALESCE(q.Score,0)) AS TotalQuestionScore,
        MAX(q.CreationDate) AS LastQuestionDate,
        SUM(COALESCE(b.Class = 1::bit OR b.Class = 2::bit, 0)) AS HighClassBadges,
        STRING_AGG(DISTINCT COALESCE(b.Name, '')) FILTER (WHERE b.Date > now() - INTERVAL '2 years') AS RecentBadges
    FROM Users u
    LEFT JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId = 1
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
ComplexPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.ClosedDate,
        -- Extract tags as array using string manipulation (Postgres)
        string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><') AS TagArray,
        -- Calculate an engagement score based on views, score, answers and age
        (p.ViewCount * 0.05 + p.Score * 2 + COALESCE(p.AnswerCount,0) * 1.5) / GREATEST(EXTRACT(day FROM now()-p.CreationDate),1) AS EngagementScore
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
PostHistoryCloseCounts AS (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotes,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenVotes,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 12) AS Deletes,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 13) AS Undeletes
    FROM PostHistory ph
    GROUP BY ph.PostId
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN a.Score > 10 THEN 1 ELSE 0 END) AS HighScoreAnswerCount
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
UserRankings AS (
    SELECT
        u.UserId,
        u.DisplayName,
        u.Reputation,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        RANK() OVER (ORDER BY u.QuestionCount DESC) AS QuestionCountRank,
        RANK() OVER (ORDER BY u.AnswerCount DESC) AS AnswerCountRank
    FROM UserQuestionStats u
),
LatestCommentsPerPost AS (
    SELECT DISTINCT ON (c.PostId)
        c.PostId,
        c.Id AS CommentId,
        c.Text,
        c.CreationDate,
        c.UserId,
        c.UserDisplayName
    FROM Comments c
    ORDER BY c.PostId, c.CreationDate DESC
),
DuplicatedPosts AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name AS LinkTypeName,
        p1.Title AS PostTitle,
        p2.Title AS RelatedPostTitle
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE pl.LinkTypeId = 3
),
FinalAggregation AS (
    SELECT
        cp.Id AS PostId,
        COALESCE(u.DisplayName, 'unknown') AS OwnerDisplayName,
        cp.Title,
        cp.PostTypeId,
        cp.Score,
        cp.ViewCount,
        cp.EngagementScore,
        phcc.CloseVotes,
        phcc.ReopenVotes,
        phcc.Deletes,
        phcc.Undeletes,
        ans.AnswerCount,
        ans.AvgAnswerScore,
        ans.MaxAnswerScore,
        ans.HighScoreAnswerCount,
        lc.Text AS LatestComment,
        lc.UserDisplayName AS CommentUser,
        STRING_AGG(DISTINCT rth.TagName, ',' ORDER BY rth.Depth) AS RelatedTagsPath,
        ur.ReputationRank,
        ur.QuestionCountRank,
        ur.AnswerCountRank
    FROM ComplexPosts cp
    LEFT JOIN Users u ON u.Id = cp.OwnerUserId
    LEFT JOIN PostHistoryCloseCounts phcc ON phcc.PostId = cp.Id
    LEFT JOIN AnswerStats ans ON ans.QuestionId = cp.Id
    LEFT JOIN LatestCommentsPerPost lc ON lc.PostId = cp.Id
    LEFT JOIN RecursiveTagHierarchy rth ON rth.TagName = ANY(cp.TagArray)
    LEFT JOIN UserRankings ur ON ur.UserId = cp.OwnerUserId
    WHERE cp.EngagementScore > 1.5
    GROUP BY cp.Id, u.DisplayName, cp.Title, cp.PostTypeId, cp.Score, cp.ViewCount, cp.EngagementScore,
             phcc.CloseVotes, phcc.ReopenVotes, phcc.Deletes, phcc.Undeletes,
             ans.AnswerCount, ans.AvgAnswerScore, ans.MaxAnswerScore, ans.HighScoreAnswerCount,
             lc.Text, lc.UserDisplayName, ur.ReputationRank, ur.QuestionCountRank, ur.AnswerCountRank
)
SELECT
    fa.PostId,
    fa.Title,
    fa.OwnerDisplayName,
    fa.PostTypeId,
    fa.Score,
    fa.ViewCount,
    ROUND(fa.EngagementScore,3) AS EngagementScore,
    fa.CloseVotes,
    fa.ReopenVotes,
    fa.Deletes,
    fa.Undeletes,
    fa.AnswerCount,
    ROUND(fa.AvgAnswerScore,2) AS AvgAnswerScore,
    fa.MaxAnswerScore,
    fa.HighScoreAnswerCount,
    COALESCE(fa.LatestComment, '[No Comments]') AS LatestComment,
    COALESCE(fa.CommentUser, '[Anonymous]') AS LatestCommentUser,
    fa.RelatedTagsPath,
    fa.ReputationRank,
    fa.QuestionCountRank,
    fa.AnswerCountRank
FROM FinalAggregation fa
WHERE
    -- Complex filter with NULL checks and case-insensitive title check
    (fa.Score >= 10 OR fa.AnswerCount >= 5 OR fa.ViewCount > 1000)
    AND (fa.Title IS NOT NULL AND lower(fa.Title) NOT LIKE '%test%')
    AND (fa.CloseVotes IS NULL OR fa.CloseVotes < 3)
ORDER BY fa.EngagementScore DESC, fa.Score DESC, fa.ViewCount DESC
LIMIT 100;
